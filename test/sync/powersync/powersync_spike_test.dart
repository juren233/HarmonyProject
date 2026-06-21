import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/powersync/powersync_backend_connector.dart';
import 'package:petnote/sync/powersync/powersync_data_mapper.dart';
import 'package:petnote/sync/powersync/powersync_schema.dart';
import 'package:petnote/sync/sync_engine_mode.dart';

void main() {
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
}
