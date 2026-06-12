import 'dart:async';

import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

typedef PairingTransportFactory = SyncTransport Function(String url);

class PairingFlow {
  PairingFlow({
    required this.settingsController,
    SyncSecretStore? secretStore,
    PairingTransportFactory? transportFactory,
    this.timeout = const Duration(seconds: 12),
  })  : _secretStore = secretStore ?? MethodChannelSyncSecretStore(),
        _transportFactory = transportFactory ?? ((url) => SyncClient(url: url));

  final AppSettingsController settingsController;
  final Duration timeout;
  final SyncSecretStore _secretStore;
  final PairingTransportFactory _transportFactory;

  Future<void> joinAsPet({
    required String serverUrl,
    required String code,
    required String deviceName,
  }) async {
    final normalizedCode = code.trim();
    if (normalizedCode.length != 6) {
      throw const PairingException('请输入 6 位配对码');
    }
    final transport = _transportFactory(serverUrl.trim());
    late final StreamSubscription<SyncMessage> subscription;
    final completer = Completer<SyncMessage>();
    subscription = transport.messages.listen((message) {
      if (message.type == SyncMessageTypes.pairJoined ||
          message.type == SyncMessageTypes.pairError) {
        if (!completer.isCompleted) {
          completer.complete(message);
        }
      }
    }, onError: (Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    try {
      await transport.connect();
      transport.send(
        SyncMessage(SyncMessageTypes.pairJoin, {
          'code': normalizedCode,
          'deviceId': await settingsController.ensureDeviceId(),
          'deviceName': deviceName.trim().isEmpty ? '宠物端设备' : deviceName.trim(),
        }),
      );
      final message = await completer.future.timeout(timeout);
      if (message.type == SyncMessageTypes.pairError) {
        throw PairingException(message.payload['message'] as String? ?? '配对失败');
      }
      final householdId = message.payload['householdId'] as String?;
      final saltBase64 = message.payload['saltBase64'] as String?;
      final authToken = message.payload['authToken'] as String?;
      if (householdId == null || saltBase64 == null || authToken == null) {
        throw const PairingException('配对响应不完整');
      }
      final crypto = await SyncCrypto.deriveFromPairingCode(
        code: normalizedCode,
        saltBase64: saltBase64,
      );
      final sharedKeyBase64 = await crypto.exportKeyBase64();
      await _secretStore.saveSharedKey(sharedKeyBase64);
      await settingsController.setDeviceRole(DeviceRole.pet);
      await settingsController.saveSyncPairing(
        serverUrl: serverUrl.trim(),
        householdId: householdId,
        sharedKeyBase64: sharedKeyBase64,
        householdAuthToken: authToken,
        deviceName: deviceName.trim().isEmpty ? '宠物端设备' : deviceName.trim(),
      );
    } on TimeoutException {
      throw const PairingException('配对超时，请重新生成配对码');
    } finally {
      await subscription.cancel();
      await transport.disconnect();
    }
  }
}

class PairingException implements Exception {
  const PairingException(this.message);

  final String message;

  @override
  String toString() => 'PairingException($message)';
}
