// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_local_storage.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/powersync/powersync_backend_connector.dart';
import 'package:petnote/sync/powersync/powersync_data_mapper.dart';
import 'package:petnote/sync/powersync/powersync_schema.dart';
import 'package:petnote/sync/powersync/powersync_spike_adapter.dart';
import 'package:petnote/sync/powersync/powersync_spike_service.dart';
import 'package:petnote/sync/sync_engine_mode.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PowerSync schema', () {
    test('覆盖 PetNote 核心表和头像 metadata 表', () {
      petNotePowerSyncSchema.validate();

      final tableNames =
          petNotePowerSyncSchema.tables.map((table) => table.name).toSet();
      expect(
        tableNames,
        containsAll({
          powerSyncPetsTable,
          powerSyncTodosTable,
          powerSyncRemindersTable,
          powerSyncRecordsTable,
          powerSyncDevicesTable,
          powerSyncPetPhotoAssetsTable,
        }),
      );
      for (final table in petNotePowerSyncSchema.tables) {
        expect(
            table.columns.map((column) => column.name), isNot(contains('id')));
      }
    });
  });

  group('PowerSync connector', () {
    test('从现有 ws/wss sync server url 推导 HTTP base uri', () {
      expect(
        powerSyncBaseUriFromSyncServerUrl('wss://sync.example.com/ws')
            .toString(),
        'https://sync.example.com/',
      );
      expect(
        powerSyncBaseUriFromSyncServerUrl('ws://127.0.0.1:8787/ws').toString(),
        'http://127.0.0.1:8787/',
      );
      expect(powerSyncBaseUriFromSyncServerUrl('ftp://example.com/ws'), isNull);
    });

    test('identity 不完整时不获取 credentials', () async {
      final connector = PetNotePowerSyncConnector(
        syncServerUrl: 'wss://sync.example.com/ws',
        householdId: null,
        authToken: 'auth-token',
        deviceId: 'device-1',
        role: 'owner',
        postJson: (_, __) async => fail('should not post credentials'),
      );

      expect(await connector.fetchCredentials(), isNull);
    });

    test('credentials 请求复用 household/device 身份', () async {
      late Uri requestedUri;
      late Map<String, dynamic> requestedBody;
      final connector = PetNotePowerSyncConnector(
        syncServerUrl: 'wss://sync.example.com/ws',
        householdId: 'household-1',
        authToken: 'auth-token',
        deviceId: 'device-1',
        role: 'owner',
        postJson: (uri, body) async {
          requestedUri = uri;
          requestedBody = body;
          return jsonEncode({
            'endpoint': 'https://powersync.example.com',
            'token': 'header.payload.signature',
            'user_id': 'device-1',
          });
        },
      );

      final credentials = await connector.fetchCredentials();

      expect(requestedUri.toString(),
          'https://sync.example.com/powersync/credentials');
      expect(requestedBody, {
        'householdId': 'household-1',
        'authToken': 'auth-token',
        'deviceId': 'device-1',
        'role': 'owner',
      });
      expect(credentials?.endpoint, 'https://powersync.example.com');
      expect(credentials?.userId, 'device-1');
    });

    test('uploadOperations 发送 PowerSync CRUD payload', () async {
      late Uri requestedUri;
      late Map<String, dynamic> requestedBody;
      final connector = PetNotePowerSyncConnector(
        syncServerUrl: 'ws://127.0.0.1:8787/ws',
        householdId: 'household-1',
        authToken: 'auth-token',
        deviceId: 'pet-device',
        role: 'pet',
        postJson: (uri, body) async {
          requestedUri = uri;
          requestedBody = body;
          return '{}';
        },
      );

      await connector.uploadOperations([
        {
          'op_id': 1,
          'op': 'PUT',
          'type': 'todos',
          'id': 'todo-1',
          'data': {'payload_json': '{"id":"todo-1"}'},
        }
      ]);

      expect(requestedUri.toString(), 'http://127.0.0.1:8787/powersync/upload');
      expect(requestedBody['householdId'], 'household-1');
      expect(requestedBody['deviceId'], 'pet-device');
      expect(requestedBody['role'], 'pet');
      expect(requestedBody['operations'], hasLength(1));
    });
  });

  group('PowerSync data mapper', () {
    test('PetNoteDataState 可以往返映射到 PowerSync 行', () {
      final sourceState = PetNoteStore.seeded().exportDataState();
      final rowsByTable = powerSyncRowsFromDataState(
        state: sourceState,
        householdId: 'household-1',
        ownerDeviceId: 'device-1',
        updatedAtMs: 1780000000000,
      );

      final restored = dataStateFromPowerSyncRows(
        pets: rowsByTable[powerSyncPetsTable]!,
        todos: rowsByTable[powerSyncTodosTable]!,
        reminders: rowsByTable[powerSyncRemindersTable]!,
        records: rowsByTable[powerSyncRecordsTable]!,
      );

      expect(restored.pets.map((pet) => pet.id), ['pet-1', 'pet-2']);
      expect(
        restored.todos.map((todo) => todo.id),
        sourceState.todos.map((todo) => todo.id),
      );
      expect(restored.reminders, hasLength(sourceState.reminders.length));
      expect(restored.records, hasLength(sourceState.records.length));
    });

    test('deleted_at_ms 非空的行不会回填到 PetNoteDataState', () {
      final sourceState = PetNoteStore.seeded().exportDataState();
      final rowsByTable = powerSyncRowsFromDataState(
        state: sourceState,
        householdId: 'household-1',
        ownerDeviceId: 'device-1',
        updatedAtMs: 1780000000000,
      );
      rowsByTable[powerSyncPetsTable]!.first['deleted_at_ms'] = 1780000000010;

      final restored = dataStateFromPowerSyncRows(
        pets: rowsByTable[powerSyncPetsTable]!,
      );

      expect(restored.pets.map((pet) => pet.id), ['pet-2']);
    });
  });

  test('SyncEngineMode 默认保留 legacy，PowerSync 仅为 spike flag', () {
    expect(SyncEngineMode.values.first, SyncEngineMode.legacy);
    expect(SyncEngineMode.values, contains(SyncEngineMode.powersyncSpike));
  });

  test('AppSettings 可持久化选择 PowerSync spike 引擎', () async {
    final settings = await AppSettingsController.load();

    expect(settings.syncEngineMode, SyncEngineMode.legacy);

    await settings.setSyncEngineMode(SyncEngineMode.powersyncSpike);
    final reloaded = await AppSettingsController.load();

    expect(reloaded.syncEngineMode, SyncEngineMode.powersyncSpike);
  });

  group('PowerSync runtime service', () {
    test('启动时远端为空会把本地 store 镜像到 PowerSync', () async {
      final settings = await _pairedSettings(role: DeviceRole.owner);
      final store = PetNoteStore.seeded();
      final bridge = _FakePowerSyncBridge(_emptyState());
      final service = PowerSyncSpikeService(
        settings: settings,
        bridgeOpener: ({required connector}) async => bridge,
        mirrorThrottle: Duration.zero,
      );

      await service.ensureStarted(store: store);

      expect(service.isActive, isTrue);
      expect(bridge.mirroredStates, hasLength(1));
      expect(bridge.mirroredStates.single.pets.map((pet) => pet.id),
          ['pet-1', 'pet-2']);

      await service.stop();
      service.dispose();
    });

    test('宠物端启动时远端暂为空不会把空本地 store 镜像到 PowerSync', () async {
      final settings = await _pairedSettings(role: DeviceRole.pet);
      final store =
          await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
      addTearDown(store.dispose);
      final bridge = _FakePowerSyncBridge(_emptyState());
      final service = PowerSyncSpikeService(
        settings: settings,
        bridgeOpener: ({required connector}) async => bridge,
        mirrorThrottle: Duration.zero,
      );

      await service.ensureStarted(store: store);

      expect(service.isActive, isTrue);
      expect(bridge.mirroredStates, isEmpty);

      await service.stop();
      service.dispose();
    });

    test('启动时远端已有数据会回填 PetNoteStore', () async {
      final settings = await _pairedSettings(role: DeviceRole.pet);
      final store =
          await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
      addTearDown(store.dispose);
      final remoteState = PetNoteStore.seeded().exportDataState();
      final bridge = _FakePowerSyncBridge(remoteState);
      final service = PowerSyncSpikeService(
        settings: settings,
        bridgeOpener: ({required connector}) async => bridge,
        mirrorThrottle: Duration.zero,
      );

      await service.ensureStarted(store: store);

      expect(store.pets.map((pet) => pet.id), ['pet-1', 'pet-2']);
      expect(bridge.mirroredStates, isEmpty);

      await service.stop();
      service.dispose();
    });

    test('store 后续变更会继续镜像到 PowerSync', () async {
      final settings = await _pairedSettings(role: DeviceRole.owner);
      final store =
          await PetNoteStore.load(storage: PetNoteLocalStorage.memory());
      addTearDown(store.dispose);
      final bridge = _FakePowerSyncBridge(_emptyState());
      final service = PowerSyncSpikeService(
        settings: settings,
        bridgeOpener: ({required connector}) async => bridge,
        mirrorThrottle: Duration.zero,
      );
      await service.ensureStarted(store: store);

      await store.addPet(
        name: 'Mochi',
        type: PetType.cat,
        breed: '英短',
        sex: '妹妹',
        birthday: '2025-01-02',
        weightKg: 4.2,
        neuterStatus: PetNeuterStatus.neutered,
        feedingPreferences: '少量多餐',
        allergies: '无',
        note: '活泼',
      );
      await Future<void>.delayed(Duration.zero);

      expect(bridge.mirroredStates.last.pets.map((pet) => pet.name),
          contains('Mochi'));

      await service.stop();
      service.dispose();
    });
  });
}

Future<AppSettingsController> _pairedSettings(
    {required DeviceRole role}) async {
  final settings = await AppSettingsController.load();
  await settings.setDeviceRole(role);
  await settings.setSyncEngineMode(SyncEngineMode.powersyncSpike);
  await settings.setSyncServerMode(SyncServerMode.custom);
  await settings.setSyncServerUrl('ws://127.0.0.1:18787/ws');
  await settings.setHouseholdId('household-1');
  await settings.setHouseholdAuthToken('auth-token');
  await settings.ensureDeviceId();
  return settings;
}

PetNoteDataState _emptyState() {
  return const PetNoteDataState(
    pets: [],
    todos: [],
    reminders: [],
    records: [],
  );
}

class _FakePowerSyncBridge implements PowerSyncSpikeDataBridge {
  _FakePowerSyncBridge(this._state);

  PetNoteDataState _state;
  @override
  final ValueNotifier<SyncStatus> status =
      ValueNotifier<SyncStatus>(const SyncStatus(connected: true));
  final List<PetNoteDataState> mirroredStates = <PetNoteDataState>[];
  final StreamController<PetNoteDataState> _controller =
      StreamController<PetNoteDataState>.broadcast();

  @override
  Future<PetNoteDataState> readDataState() async => _state;

  @override
  Stream<PetNoteDataState> watchDataState({
    Duration throttle = const Duration(milliseconds: 250),
  }) {
    return _controller.stream;
  }

  @override
  Future<void> mirrorLocalDataState({
    required PetNoteDataState state,
    required String householdId,
    required String ownerDeviceId,
    required int updatedAtMs,
    String role = 'owner',
  }) async {
    _state = state;
    mirroredStates.add(state);
    _controller.add(state);
  }

  @override
  Future<void> close() async {
    status.dispose();
    await _controller.close();
  }
}
