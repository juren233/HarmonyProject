import 'dart:convert';

import 'package:postgres/postgres.dart';

class PowerSyncUploadRequest {
  const PowerSyncUploadRequest({
    required this.householdId,
    required this.deviceId,
    required this.role,
    required this.operations,
  });

  final String householdId;
  final String deviceId;
  final String role;
  final List<PowerSyncUploadOperation> operations;

  int get rolePriority => switch (role) {
        'owner' => 20,
        'pet' => 10,
        _ => 0,
      };
}

class PowerSyncUploadOperation {
  const PowerSyncUploadOperation({
    required this.clientOpId,
    required this.operation,
    required this.table,
    required this.id,
    required this.data,
  });

  final String clientOpId;
  final String operation;
  final String table;
  final String id;
  final Map<String, dynamic> data;

  factory PowerSyncUploadOperation.fromJson(Map<String, dynamic> json) {
    final opId = json['client_op_id'] ?? json['op_id'];
    final operation = json['op'];
    final table = json['table'] ?? json['type'];
    final id = json['id'];
    final data = json['data'];
    if (opId == null ||
        operation is! String ||
        table is! String ||
        id is! String) {
      throw const FormatException('invalid powersync operation');
    }
    return PowerSyncUploadOperation(
      clientOpId: opId.toString(),
      operation: operation,
      table: table,
      id: id,
      data: data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }
}

class PowerSyncUploadResult {
  const PowerSyncUploadResult({
    required this.applied,
    required this.skipped,
  });

  final int applied;
  final int skipped;
}

abstract class PowerSyncUploadRepository {
  bool get isConfigured;

  Future<PowerSyncUploadResult> applyUpload(PowerSyncUploadRequest request);

  Future<void> close();
}

class DisabledPowerSyncUploadRepository implements PowerSyncUploadRepository {
  const DisabledPowerSyncUploadRepository();

  @override
  bool get isConfigured => false;

  @override
  Future<PowerSyncUploadResult> applyUpload(PowerSyncUploadRequest request) {
    throw StateError('powersync database not configured');
  }

  @override
  Future<void> close() async {}
}

class PostgresPowerSyncUploadRepository implements PowerSyncUploadRepository {
  PostgresPowerSyncUploadRepository(this._pool);

  factory PostgresPowerSyncUploadRepository.fromConnectionString(String url) {
    return PostgresPowerSyncUploadRepository(Pool.withUrl(url));
  }

  static PowerSyncUploadRepository fromEnvironment(Map<String, String> env) {
    final url = env['POWERSYNC_DATABASE_URL']?.trim();
    if (url == null || url.isEmpty) {
      return const DisabledPowerSyncUploadRepository();
    }
    return PostgresPowerSyncUploadRepository.fromConnectionString(url);
  }

  final Pool _pool;

  @override
  bool get isConfigured => true;

  @override
  Future<PowerSyncUploadResult> applyUpload(
    PowerSyncUploadRequest request,
  ) async {
    return _pool.runTx((session) async {
      var applied = 0;
      var skipped = 0;
      for (final operation in request.operations) {
        final clientOpId =
            '${request.deviceId}:${operation.clientOpId}:${operation.table}:${operation.id}';
        final inserted = await session.execute(
          Sql.named(
            'INSERT INTO powersync_client_ops '
            '(client_op_id, household_id, device_id, table_name, row_id, operation, applied_at_ms) '
            'VALUES (@clientOpId, @householdId, @deviceId, @tableName, @rowId, @operation, @appliedAtMs) '
            'ON CONFLICT (client_op_id) DO NOTHING',
          ),
          parameters: {
            'clientOpId': clientOpId,
            'householdId': request.householdId,
            'deviceId': request.deviceId,
            'tableName': operation.table,
            'rowId': operation.id,
            'operation': operation.operation,
            'appliedAtMs': DateTime.now().millisecondsSinceEpoch,
          },
        );
        if (inserted.affectedRows == 0) {
          skipped += 1;
          continue;
        }
        await _applyOperation(session, request, operation);
        applied += 1;
      }
      return PowerSyncUploadResult(applied: applied, skipped: skipped);
    });
  }

  Future<void> _applyOperation(
    TxSession session,
    PowerSyncUploadRequest request,
    PowerSyncUploadOperation operation,
  ) async {
    final table = _allowedTables[operation.table];
    if (table == null) {
      throw FormatException('unsupported powersync table ${operation.table}');
    }
    if (operation.operation == 'DELETE') {
      await _softDelete(session, table, request, operation);
      return;
    }
    if (operation.operation != 'PUT' && operation.operation != 'PATCH') {
      throw FormatException(
          'unsupported powersync operation ${operation.operation}');
    }
    if (table == 'devices') {
      await _upsertDevice(session, request, operation);
      return;
    }
    await _upsertContent(session, table, request, operation);
  }

  Future<void> _upsertContent(
    TxSession session,
    String table,
    PowerSyncUploadRequest request,
    PowerSyncUploadOperation operation,
  ) async {
    final payloadJson = _payloadJson(operation.data);
    final updatedAtMs = _updatedAtMs(operation.data);
    await session.execute(
      Sql.named(
        'INSERT INTO $table '
        '(id, household_id, payload_json, updated_at_ms, deleted_at_ms, owner_device_id, role_priority) '
        'VALUES (@id, @householdId, CAST(@payloadJson AS jsonb), @updatedAtMs, NULL, @deviceId, @rolePriority) '
        'ON CONFLICT (id) DO UPDATE SET '
        'payload_json = CASE WHEN '
        'excluded.updated_at_ms > $table.updated_at_ms OR '
        '(excluded.updated_at_ms = $table.updated_at_ms AND excluded.role_priority >= $table.role_priority) '
        'THEN excluded.payload_json ELSE $table.payload_json END, '
        'household_id = CASE WHEN excluded.updated_at_ms >= $table.updated_at_ms THEN excluded.household_id ELSE $table.household_id END, '
        'updated_at_ms = GREATEST($table.updated_at_ms, excluded.updated_at_ms), '
        'deleted_at_ms = CASE WHEN excluded.updated_at_ms >= $table.updated_at_ms THEN NULL ELSE $table.deleted_at_ms END, '
        'owner_device_id = CASE WHEN excluded.updated_at_ms >= $table.updated_at_ms THEN excluded.owner_device_id ELSE $table.owner_device_id END, '
        'role_priority = GREATEST($table.role_priority, excluded.role_priority)',
      ),
      parameters: {
        'id': operation.id,
        'householdId': request.householdId,
        'payloadJson': payloadJson,
        'updatedAtMs': updatedAtMs,
        'deviceId': request.deviceId,
        'rolePriority': request.rolePriority,
      },
    );
  }

  Future<void> _upsertDevice(
    TxSession session,
    PowerSyncUploadRequest request,
    PowerSyncUploadOperation operation,
  ) async {
    final payloadJson = _payloadJson(operation.data);
    final updatedAtMs = _updatedAtMs(operation.data);
    await session.execute(
      Sql.named(
        'INSERT INTO devices '
        '(id, household_id, payload_json, role, served_pet_id, updated_at_ms, deleted_at_ms) '
        'VALUES (@id, @householdId, CAST(@payloadJson AS jsonb), @role, @servedPetId, @updatedAtMs, NULL) '
        'ON CONFLICT (id) DO UPDATE SET '
        'payload_json = excluded.payload_json, '
        'household_id = excluded.household_id, '
        'role = excluded.role, '
        'served_pet_id = excluded.served_pet_id, '
        'updated_at_ms = GREATEST(devices.updated_at_ms, excluded.updated_at_ms), '
        'deleted_at_ms = NULL',
      ),
      parameters: {
        'id': operation.id,
        'householdId': request.householdId,
        'payloadJson': payloadJson,
        'role': operation.data['role'] as String? ?? request.role,
        'servedPetId': operation.data['served_pet_id'] as String?,
        'updatedAtMs': updatedAtMs,
      },
    );
  }

  Future<void> _softDelete(
    TxSession session,
    String table,
    PowerSyncUploadRequest request,
    PowerSyncUploadOperation operation,
  ) async {
    await session.execute(
      Sql.named(
        'UPDATE $table SET deleted_at_ms=@deletedAtMs '
        'WHERE id=@id AND household_id=@householdId',
      ),
      parameters: {
        'id': operation.id,
        'householdId': request.householdId,
        'deletedAtMs': _updatedAtMs(operation.data),
      },
    );
  }

  @override
  Future<void> close() => _pool.close();
}

const Map<String, String> _allowedTables = {
  'pets': 'pets',
  'todos': 'todos',
  'reminders': 'reminders',
  'records': 'records',
  'devices': 'devices',
  'pet_photo_assets': 'pet_photo_assets',
};

String _payloadJson(Map<String, dynamic> data) {
  final payload = data['payload_json'];
  if (payload is String && payload.trim().isNotEmpty) {
    return payload;
  }
  if (payload is Map) {
    return jsonEncode(payload);
  }
  return jsonEncode(data);
}

int _updatedAtMs(Map<String, dynamic> data) {
  final value = data['updated_at_ms'] ?? data['updatedAtMs'];
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}
