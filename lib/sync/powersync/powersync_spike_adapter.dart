import 'package:path_provider/path_provider.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/sync/powersync/powersync_backend_connector.dart';
import 'package:petnote/sync/powersync/powersync_data_mapper.dart';
import 'package:petnote/sync/powersync/powersync_schema.dart';
import 'package:powersync/powersync.dart';

class PetNotePowerSyncSpikeAdapter {
  PetNotePowerSyncSpikeAdapter(this.database);

  final PowerSyncDatabase database;

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

  Future<void> close() => database.close();
}

Future<String> _defaultDatabasePath() async {
  final directory = await getApplicationSupportDirectory();
  return '${directory.path}/petnote-powersync-spike.db';
}
