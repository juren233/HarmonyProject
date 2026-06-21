import 'package:powersync/powersync.dart';

const String powerSyncPetsTable = 'pets';
const String powerSyncTodosTable = 'todos';
const String powerSyncRemindersTable = 'reminders';
const String powerSyncRecordsTable = 'records';
const String powerSyncDevicesTable = 'devices';
const String powerSyncPetPhotoAssetsTable = 'pet_photo_assets';

final Schema petNotePowerSyncSchema = Schema([
  _contentTable(powerSyncPetsTable),
  _contentTable(powerSyncTodosTable),
  _contentTable(powerSyncRemindersTable),
  _contentTable(powerSyncRecordsTable),
  Table(
    powerSyncDevicesTable,
    const [
      Column.text('household_id'),
      Column.text('payload_json'),
      Column.text('role'),
      Column.text('served_pet_id'),
      Column.integer('updated_at_ms'),
      Column.integer('deleted_at_ms'),
    ],
    indexes: [
      Index.ascending('devices_household_updated', [
        'household_id',
        'updated_at_ms',
      ]),
    ],
  ),
  Table(
    powerSyncPetPhotoAssetsTable,
    const [
      Column.text('household_id'),
      Column.text('pet_id'),
      Column.text('payload_json'),
      Column.integer('updated_at_ms'),
      Column.integer('deleted_at_ms'),
      Column.text('owner_device_id'),
      Column.integer('role_priority'),
    ],
    indexes: [
      Index.ascending('pet_photo_assets_household_pet', [
        'household_id',
        'pet_id',
      ]),
    ],
  ),
]);

Table _contentTable(String name) {
  return Table(
    name,
    const [
      Column.text('household_id'),
      Column.text('payload_json'),
      Column.integer('updated_at_ms'),
      Column.integer('deleted_at_ms'),
      Column.text('owner_device_id'),
      Column.integer('role_priority'),
    ],
    indexes: [
      Index.ascending('${name}_household_updated', [
        'household_id',
        'updated_at_ms',
      ]),
    ],
  );
}
