// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/sync/powersync/powersync_backend_connector.dart';
import 'package:petnote/sync/powersync/powersync_data_mapper.dart';
import 'package:petnote/sync/powersync/powersync_schema.dart';
import 'package:powersync/powersync.dart';

abstract class PowerSyncSpikeDataBridge {
  ValueListenable<SyncStatus> get status;

  Future<PetNoteDataState> readDataState();

  Stream<PetNoteDataState> watchDataState({
    Duration throttle = const Duration(milliseconds: 250),
  });

  Future<void> mirrorLocalDataState({
    required PetNoteDataState state,
    required String householdId,
    required String ownerDeviceId,
    required int updatedAtMs,
    String role = 'owner',
  });

  Future<void> close();
}

class PetNotePowerSyncSpikeAdapter implements PowerSyncSpikeDataBridge {
  PetNotePowerSyncSpikeAdapter(this.database) {
    _statusSubscription = database.statusStream.listen((status) {
      _status.value = status;
    });
    _status.value = database.currentStatus;
  }

  final PowerSyncDatabase database;
  final ValueNotifier<SyncStatus> _status = ValueNotifier<SyncStatus>(
    const SyncStatus(),
  );
  StreamSubscription<SyncStatus>? _statusSubscription;

  @override
  ValueListenable<SyncStatus> get status => _status;

  static Future<PetNotePowerSyncSpikeAdapter> open({
    required PetNotePowerSyncConnector connector,
    String? path,
  }) async {
    final resolvedPath = path ?? await _defaultDatabasePath();
    final database = PowerSyncDatabase(
      schema: petNotePowerSyncSchema,
      path: resolvedPath,
    );
    await database.initialize();
    await database.connect(connector: connector);
    return PetNotePowerSyncSpikeAdapter(database);
  }

  @override
  Future<PetNoteDataState> readDataState() async {
    Future<List<Map<String, dynamic>>> readRows(String table) async {
      final rows = await database.getAll(
        'SELECT * FROM $table WHERE deleted_at_ms IS NULL',
      );
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    }

    return dataStateFromPowerSyncRows(
      pets: await readRows(powerSyncPetsTable),
      todos: await readRows(powerSyncTodosTable),
      reminders: await readRows(powerSyncRemindersTable),
      records: await readRows(powerSyncRecordsTable),
    );
  }

  @override
  Stream<PetNoteDataState> watchDataState({
    Duration throttle = const Duration(milliseconds: 250),
  }) async* {
    yield await readDataState();
    await for (final _ in database.watch(
      'SELECT id, updated_at_ms FROM $powerSyncPetsTable '
      'UNION ALL SELECT id, updated_at_ms FROM $powerSyncTodosTable '
      'UNION ALL SELECT id, updated_at_ms FROM $powerSyncRemindersTable '
      'UNION ALL SELECT id, updated_at_ms FROM $powerSyncRecordsTable',
      throttle: throttle,
      triggerOnTables: const [
        powerSyncPetsTable,
        powerSyncTodosTable,
        powerSyncRemindersTable,
        powerSyncRecordsTable,
      ],
    )) {
      yield await readDataState();
    }
  }

  @override
  Future<void> mirrorLocalDataState({
    required PetNoteDataState state,
    required String householdId,
    required String ownerDeviceId,
    required int updatedAtMs,
    String role = 'owner',
  }) async {
    final rowsByTable = powerSyncRowsFromDataState(
      state: state,
      householdId: householdId,
      ownerDeviceId: ownerDeviceId,
      updatedAtMs: updatedAtMs,
      role: role,
    );
    await database.writeTransaction((tx) async {
      for (final table in const [
        powerSyncPetsTable,
        powerSyncTodosTable,
        powerSyncRemindersTable,
        powerSyncRecordsTable,
      ]) {
        final rows = rowsByTable[table] ?? const <Map<String, dynamic>>[];
        final activeIds = <String>[];
        for (final row in rows) {
          final id = row['id'];
          if (id is String && id.isNotEmpty) {
            activeIds.add(id);
          }
          await tx.execute(
            'INSERT OR REPLACE INTO $table '
            '(id, household_id, payload_json, updated_at_ms, deleted_at_ms, owner_device_id, role_priority) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              row['id'],
              row['household_id'],
              row['payload_json'],
              row['updated_at_ms'],
              row['deleted_at_ms'],
              row['owner_device_id'],
              row['role_priority'],
            ],
          );
        }
        await _deleteRowsNotIn(
          tx,
          table: table,
          activeIds: activeIds,
        );
      }

      final photoRows = rowsByTable[powerSyncPetPhotoAssetsTable] ??
          const <Map<String, dynamic>>[];
      final activePhotoIds = <String>[];
      for (final row in photoRows) {
        final id = row['id'];
        if (id is String && id.isNotEmpty) {
          activePhotoIds.add(id);
        }
        await tx.execute(
          'INSERT OR REPLACE INTO $powerSyncPetPhotoAssetsTable '
          '(id, household_id, pet_id, payload_json, updated_at_ms, deleted_at_ms, owner_device_id, role_priority) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['household_id'],
            row['pet_id'],
            row['payload_json'],
            row['updated_at_ms'],
            row['deleted_at_ms'],
            row['owner_device_id'],
            row['role_priority'],
          ],
        );
      }
      await _deleteRowsNotIn(
        tx,
        table: powerSyncPetPhotoAssetsTable,
        activeIds: activePhotoIds,
      );
    });
  }

  Future<void> replaceLocalDataState({
    required PetNoteDataState state,
    required String householdId,
    required String ownerDeviceId,
    required int updatedAtMs,
    String role = 'owner',
  }) async {
    final rowsByTable = powerSyncRowsFromDataState(
      state: state,
      householdId: householdId,
      ownerDeviceId: ownerDeviceId,
      updatedAtMs: updatedAtMs,
      role: role,
    );
    await database.writeTransaction((tx) async {
      for (final table in const [
        powerSyncPetsTable,
        powerSyncTodosTable,
        powerSyncRemindersTable,
        powerSyncRecordsTable,
        powerSyncPetPhotoAssetsTable,
      ]) {
        await tx.execute('DELETE FROM $table');
      }
      for (final table in const [
        powerSyncPetsTable,
        powerSyncTodosTable,
        powerSyncRemindersTable,
        powerSyncRecordsTable,
      ]) {
        for (final row
            in rowsByTable[table] ?? const <Map<String, dynamic>>[]) {
          await tx.execute(
            'INSERT INTO $table '
            '(id, household_id, payload_json, updated_at_ms, deleted_at_ms, owner_device_id, role_priority) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              row['id'],
              row['household_id'],
              row['payload_json'],
              row['updated_at_ms'],
              row['deleted_at_ms'],
              row['owner_device_id'],
              row['role_priority'],
            ],
          );
        }
      }
      for (final row in rowsByTable[powerSyncPetPhotoAssetsTable] ??
          const <Map<String, dynamic>>[]) {
        await tx.execute(
          'INSERT INTO $powerSyncPetPhotoAssetsTable '
          '(id, household_id, pet_id, payload_json, updated_at_ms, deleted_at_ms, owner_device_id, role_priority) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['household_id'],
            row['pet_id'],
            row['payload_json'],
            row['updated_at_ms'],
            row['deleted_at_ms'],
            row['owner_device_id'],
            row['role_priority'],
          ],
        );
      }
    });
  }

  @override
  Future<void> close() async {
    await _statusSubscription?.cancel();
    _status.dispose();
    await database.close();
  }
}

Future<void> _deleteRowsNotIn(
  dynamic tx, {
  required String table,
  required List<String> activeIds,
}) async {
  if (activeIds.isEmpty) {
    await tx.execute('DELETE FROM $table');
    return;
  }
  final placeholders = List<String>.filled(activeIds.length, '?').join(', ');
  await tx.execute(
    'DELETE FROM $table WHERE id NOT IN ($placeholders)',
    activeIds,
  );
}

Future<String> _defaultDatabasePath() async {
  final directory = await getApplicationSupportDirectory();
  return '${directory.path}/petnote-powersync-spike.db';
}
