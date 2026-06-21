import 'dart:convert';

import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/powersync/powersync_schema.dart';

PetNoteDataState dataStateFromPowerSyncRows({
  Iterable<Map<String, dynamic>> pets = const [],
  Iterable<Map<String, dynamic>> todos = const [],
  Iterable<Map<String, dynamic>> reminders = const [],
  Iterable<Map<String, dynamic>> records = const [],
}) {
  return PetNoteDataState(
    pets: _decodeRows(pets, Pet.fromJson),
    todos: _decodeRows(todos, TodoItem.fromJson),
    reminders: _decodeRows(reminders, ReminderItem.fromJson),
    records: _decodeRows(records, PetRecord.fromJson),
  );
}

Map<String, List<Map<String, dynamic>>> powerSyncRowsFromDataState({
  required PetNoteDataState state,
  required String householdId,
  required String ownerDeviceId,
  required int updatedAtMs,
  String role = 'owner',
}) {
  final rolePriority = switch (role) {
    'owner' => 20,
    'pet' => 10,
    _ => 0,
  };
  return {
    powerSyncPetsTable: [
      for (final pet in state.pets)
        _contentRow(
          householdId: householdId,
          ownerDeviceId: ownerDeviceId,
          updatedAtMs: updatedAtMs,
          rolePriority: rolePriority,
          payload: pet.toJson(),
        ),
    ],
    powerSyncTodosTable: [
      for (final todo in state.todos)
        _contentRow(
          householdId: householdId,
          ownerDeviceId: ownerDeviceId,
          updatedAtMs: updatedAtMs,
          rolePriority: rolePriority,
          payload: todo.toJson(),
        ),
    ],
    powerSyncRemindersTable: [
      for (final reminder in state.reminders)
        _contentRow(
          householdId: householdId,
          ownerDeviceId: ownerDeviceId,
          updatedAtMs: updatedAtMs,
          rolePriority: rolePriority,
          payload: reminder.toJson(),
        ),
    ],
    powerSyncRecordsTable: [
      for (final record in state.records)
        _contentRow(
          householdId: householdId,
          ownerDeviceId: ownerDeviceId,
          updatedAtMs: updatedAtMs,
          rolePriority: rolePriority,
          payload: record.toJson(),
        ),
    ],
    powerSyncPetPhotoAssetsTable: [
      for (final pet in state.pets)
        if (pet.photoPath != null && pet.photoPath!.isNotEmpty)
          {
            'id': '${pet.id}:avatar',
            'household_id': householdId,
            'pet_id': pet.id,
            'payload_json': jsonEncode({
              'id': '${pet.id}:avatar',
              'petId': pet.id,
              'kind': 'avatar',
              'path': pet.photoPath,
            }),
            'updated_at_ms': updatedAtMs,
            'deleted_at_ms': null,
            'owner_device_id': ownerDeviceId,
            'role_priority': rolePriority,
          },
    ],
  };
}

List<T> _decodeRows<T>(
  Iterable<Map<String, dynamic>> rows,
  T Function(Map<String, dynamic> json) decode,
) {
  final values = <T>[];
  for (final row in rows) {
    if (_isDeleted(row)) {
      continue;
    }
    final payload = _payloadFromRow(row);
    if (payload == null) {
      continue;
    }
    values.add(decode(payload));
  }
  return values;
}

bool _isDeleted(Map<String, dynamic> row) {
  final deletedAt = row['deleted_at_ms'];
  if (deletedAt is num) {
    return deletedAt.toInt() > 0;
  }
  if (deletedAt is String) {
    return (int.tryParse(deletedAt) ?? 0) > 0;
  }
  return false;
}

Map<String, dynamic>? _payloadFromRow(Map<String, dynamic> row) {
  final payload = row['payload_json'];
  if (payload is String && payload.trim().isNotEmpty) {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  }
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  if (payload is Map) {
    return Map<String, dynamic>.from(payload);
  }
  return null;
}

Map<String, dynamic> _contentRow({
  required String householdId,
  required String ownerDeviceId,
  required int updatedAtMs,
  required int rolePriority,
  required Map<String, dynamic> payload,
}) {
  return {
    'id': payload['id'],
    'household_id': householdId,
    'payload_json': jsonEncode(payload),
    'updated_at_ms': updatedAtMs,
    'deleted_at_ms': null,
    'owner_device_id': ownerDeviceId,
    'role_priority': rolePriority,
  };
}
