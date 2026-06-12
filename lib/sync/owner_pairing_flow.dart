import 'dart:async';

import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/sync/pairing_flow.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

typedef PairingPeerJoined = void Function(String deviceId, String deviceName);

class OwnerPairingSession {
  const OwnerPairingSession({
    required this.code,
    required this.expiresAtMs,
    required this.householdId,
  });

  final String code;
  final int expiresAtMs;
  final String householdId;
}

class OwnerPairingFlow {
  OwnerPairingFlow({
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

  SyncTransport? _transport;
  StreamSubscription<SyncMessage>? _subscription;
  PairingPeerJoined? _onPeerJoined;

  Future<OwnerPairingSession> createAsOwner({
    required String serverUrl,
    required String deviceName,
    PairingPeerJoined? onPeerJoined,
  }) async {
    await dispose();
    _onPeerJoined = onPeerJoined;
    final transport = _transportFactory(serverUrl.trim());
    _transport = transport;
    final completer = Completer<SyncMessage>();
    _subscription = transport.messages.listen((message) {
      if (message.type == SyncMessageTypes.pairCreated ||
          message.type == SyncMessageTypes.pairError) {
        if (!completer.isCompleted) {
          completer.complete(message);
        }
        return;
      }
      if (message.type == SyncMessageTypes.pairPeerJoined) {
        final deviceId = message.payload['deviceId'] as String? ?? '';
        final peerName = message.payload['deviceName'] as String? ?? '宠物端设备';
        _onPeerJoined?.call(deviceId, peerName);
      }
    }, onError: (Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    await transport.connect();
    await settingsController.setDeviceRole(DeviceRole.owner);
    transport.send(
      SyncMessage(SyncMessageTypes.pairCreate, {
        'householdId': settingsController.householdId,
        'authToken': settingsController.householdAuthToken,
        'deviceId': await settingsController.ensureDeviceId(),
        'deviceName': deviceName.trim().isEmpty ? '主人设备' : deviceName.trim(),
      }),
    );

    try {
      final message = await completer.future.timeout(timeout);
      if (message.type == SyncMessageTypes.pairError) {
        throw PairingException(message.payload['message'] as String? ?? '配对失败');
      }
      if (message.payload['hasPetDevice'] == true) {
        throw const PairingException('请先解绑现有宠物端设备');
      }
      final code = message.payload['code'] as String?;
      final saltBase64 = message.payload['saltBase64'] as String?;
      final authToken = message.payload['authToken'] as String?;
      final householdId = message.payload['householdId'] as String?;
      final expiresAtMs = (message.payload['expiresAtMs'] as num?)?.toInt();
      if (code == null ||
          saltBase64 == null ||
          authToken == null ||
          householdId == null ||
          expiresAtMs == null) {
        throw const PairingException('配对响应不完整');
      }
      final existingKey = await _secretStore.loadSharedKey() ??
          settingsController.sharedKeyBase64;
      final sharedKeyBase64 = existingKey ??
          await (await SyncCrypto.deriveFromPairingCode(
            code: code,
            saltBase64: saltBase64,
          ))
              .exportKeyBase64();
      if (existingKey == null) {
        await _secretStore.saveSharedKey(sharedKeyBase64);
      }
      await settingsController.saveSyncPairing(
        serverUrl: serverUrl.trim(),
        householdId: householdId,
        sharedKeyBase64: sharedKeyBase64,
        householdAuthToken: authToken,
        deviceName: deviceName.trim().isEmpty ? '主人设备' : deviceName.trim(),
      );
      return OwnerPairingSession(
        code: code,
        expiresAtMs: expiresAtMs,
        householdId: householdId,
      );
    } on TimeoutException {
      throw const PairingException('生成配对码超时');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _transport?.disconnect();
    _transport = null;
    _onPeerJoined = null;
  }
}
