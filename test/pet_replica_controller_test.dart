import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('收到快照解密后写入本地 store', () async {
    final sourceStore = PetNoteStore.seeded();
    final replicaStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start();

    final state = PetNoteDataState(
      pets: sourceStore.pets,
      todos: sourceStore.todos,
      reminders: sourceStore.reminders,
      records: sourceStore.records,
    );
    transport.incoming.add(
      SyncMessage(SyncMessageTypes.snapshot, {
        'version': 1,
        'ciphertext': await crypto.encryptString(jsonEncode(state.toJson())),
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(replicaStore.pets.length, sourceStore.pets.length);
    expect(controller.lastSyncedVersion.value, 1);

    controller.dispose();
  });

  test('sendAction 加密上行并标记 pending', () async {
    final replicaStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
    )..start();

    await controller.sendAction(
      const PetAction(
        kind: PetActionKind.markDone,
        sourceType: 'todo',
        itemId: 'todo-1',
      ),
    );

    final actionMessages = transport.sent
        .where((message) => message.type == SyncMessageTypes.actionPush)
        .toList();
    expect(actionMessages, hasLength(1));
    expect(controller.pendingItemKeys.value, contains('todo:todo-1'));

    controller.dispose();
  });

  test('device_config 更新 servedPetId，removed 时清除配对', () async {
    final settings = await AppSettingsController.load();
    await settings.setSyncServerUrl('wss://example.com/ws');
    await settings.setHouseholdId('house-1');
    await settings.setServedPetId('pet-1');
    final replicaStore =
        await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
    final transport = FakeSyncTransport();
    final crypto = await SyncCrypto.deriveFromPairingCode(
      code: '123456',
      saltBase64: SyncCrypto.generateSaltBase64(),
    );
    final controller = PetReplicaController(
      store: replicaStore,
      transport: transport,
      crypto: crypto,
      settings: settings,
    )..start();

    transport.incoming.add(
      const SyncMessage(
          SyncMessageTypes.deviceConfig, {'servedPetId': 'pet-2'}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(settings.servedPetId, 'pet-2');

    transport.incoming.add(
      const SyncMessage(SyncMessageTypes.deviceConfig, {'removed': true}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.removedByOwner.value, isTrue);
    expect(settings.householdId, isNull);

    controller.dispose();
  });
}

class FakeSyncTransport implements SyncTransport {
  final List<SyncMessage> sent = <SyncMessage>[];
  final StreamController<SyncMessage> incoming =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> errorController =
      StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => errorController.stream;

  @override
  Stream<SyncMessage> get messages => incoming.stream;

  @override
  ValueListenable<SyncConnectionState> get state => _state;
  final ValueNotifier<SyncConnectionState> _state =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.disconnected);

  @override
  Future<void> connect() async {
    _state.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    _state.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) => sent.add(message);
}
