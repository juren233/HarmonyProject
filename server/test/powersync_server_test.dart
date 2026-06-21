import 'dart:convert';
import 'dart:io';

import 'package:petnote_sync_server/src/household_store.dart';
import 'package:petnote_sync_server/src/powersync_jwt.dart';
import 'package:petnote_sync_server/src/powersync_upload_repository.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:test/test.dart';

void main() {
  late SyncServerApp app;
  late HttpServer server;

  Future<void> startApp({
    PowerSyncJwtSigner? signer,
    PowerSyncUploadRepository? repository,
  }) async {
    app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_ps_srv_'),
      powerSyncJwtSigner: signer,
      powerSyncUploadRepository: repository,
      powerSyncEndpoint: 'http://127.0.0.1:8080',
    );
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
  }

  tearDown(() async {
    await app.close();
    await server.close(force: true);
  });

  test('credentials 未配置 JWT secret 时返回 503', () async {
    await startApp(signer: const PowerSyncJwtSigner(secret: ''));

    final response = await _postJson(server, '/powersync/credentials', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'owner-device',
    });

    expect(response.statusCode, 503);
    expect(response.body, contains('powersync not configured'));
  });

  test('credentials 复用 household token 和已登记设备鉴权', () async {
    await startApp(signer: _fixedSigner());
    app.store
        .create('household-1', 'salt', 'auth-token')
        .devices['owner-device'] = HouseholdDevice(
      deviceId: 'owner-device',
      name: '主人手机',
      role: 'owner',
    );

    final response = await _postJson(server, '/powersync/credentials', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'owner-device',
    });
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = _decodeJwtPayload(json['token'] as String);

    expect(response.statusCode, 200);
    expect(json['endpoint'], 'http://127.0.0.1:8080');
    expect(json['user_id'], 'owner-device');
    expect(json['expires_at_ms'], 1780000900000);
    expect(payload['sub'], 'owner-device');
    expect(payload['household_id'], 'household-1');
    expect(payload['device_id'], 'owner-device');
    expect(payload['role'], 'owner');
    expect(payload['aud'], 'powersync');
    expect(json['token'] as String, isNot(contains('test-secret')));
  });

  test('credentials 拒绝错误 token 和陌生设备', () async {
    await startApp(signer: _fixedSigner());
    app.store
        .create('household-1', 'salt', 'auth-token')
        .devices['owner-device'] = HouseholdDevice(
      deviceId: 'owner-device',
      name: '主人手机',
      role: 'owner',
    );

    final wrongToken = await _postJson(server, '/powersync/credentials', {
      'householdId': 'household-1',
      'authToken': 'wrong-token',
      'deviceId': 'owner-device',
    });
    final unknownDevice = await _postJson(server, '/powersync/credentials', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'pet-device',
    });

    expect(wrongToken.statusCode, 401);
    expect(unknownDevice.statusCode, 403);
  });

  test('upload 未配置 Postgres 时返回 503', () async {
    await startApp(signer: _fixedSigner());
    app.store
        .create('household-1', 'salt', 'auth-token')
        .devices['owner-device'] = HouseholdDevice(
      deviceId: 'owner-device',
      name: '主人手机',
      role: 'owner',
    );

    final response = await _postJson(server, '/powersync/upload', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'owner-device',
      'operations': const <Map<String, dynamic>>[],
    });

    expect(response.statusCode, 503);
    expect(response.body, contains('powersync database not configured'));
  });

  test('upload 将 PowerSync CRUD 批次交给仓储层', () async {
    final repository = _RecordingPowerSyncRepository();
    await startApp(signer: _fixedSigner(), repository: repository);
    app.store
        .create('household-1', 'salt', 'auth-token')
        .devices['pet-device'] = HouseholdDevice(
      deviceId: 'pet-device',
      name: '宠物平板',
      role: 'pet',
    );

    final response = await _postJson(server, '/powersync/upload', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'pet-device',
      'operations': [
        {
          'op_id': 9,
          'op': 'PUT',
          'type': 'todos',
          'id': 'todo-1',
          'tx_id': 3,
          'data': {
            'payload_json': '{"id":"todo-1","title":"喂食"}',
            'updated_at_ms': 1780000000000,
          },
        }
      ],
    });
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    expect(response.statusCode, 200);
    expect(json, {'applied': 1, 'skipped': 0});
    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.householdId, 'household-1');
    expect(repository.requests.single.deviceId, 'pet-device');
    expect(repository.requests.single.role, 'pet');
    expect(repository.requests.single.operations.single.table, 'todos');
  });

  test('upload 保留宠物头像附件 metadata operation', () async {
    final repository = _RecordingPowerSyncRepository();
    await startApp(signer: _fixedSigner(), repository: repository);
    app.store
        .create('household-1', 'salt', 'auth-token')
        .devices['owner-device'] = HouseholdDevice(
      deviceId: 'owner-device',
      name: '主人手机',
      role: 'owner',
    );

    final response = await _postJson(server, '/powersync/upload', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'owner-device',
      'operations': [
        {
          'op_id': 'photo-op-1',
          'op': 'PUT',
          'type': 'pet_photo_assets',
          'id': 'photo-1',
          'data': {
            'pet_id': 'pet-1',
            'payload_json': '{"relativePath":"pet_photos/photo-1.jpg"}',
            'updated_at_ms': 1780000000000,
          },
        }
      ],
    });

    expect(response.statusCode, 200);
    expect(
        repository.requests.single.operations.single.table, 'pet_photo_assets');
    expect(
        repository.requests.single.operations.single.data['pet_id'], 'pet-1');
  });

  test('upload 拒绝非对象 operation', () async {
    final repository = _RecordingPowerSyncRepository();
    await startApp(signer: _fixedSigner(), repository: repository);
    app.store
        .create('household-1', 'salt', 'auth-token')
        .devices['owner-device'] = HouseholdDevice(
      deviceId: 'owner-device',
      name: '主人手机',
      role: 'owner',
    );

    final response = await _postJson(server, '/powersync/upload', {
      'householdId': 'household-1',
      'authToken': 'auth-token',
      'deviceId': 'owner-device',
      'operations': ['bad-op'],
    });

    expect(response.statusCode, 400);
    expect(repository.requests, isEmpty);
  });

  test('PowerSync JWT 使用 HS256 并写入 household/device claims', () {
    final signed = _fixedSigner().sign(
      householdId: 'household-1',
      deviceId: 'device-1',
      role: 'owner',
    );
    final parts = signed.token.split('.');
    final header = jsonDecode(
      utf8.decode(base64Url.decode(base64.normalize(parts[0]))),
    ) as Map<String, dynamic>;
    final payload = _decodeJwtPayload(signed.token);

    expect(parts, hasLength(3));
    expect(header['alg'], 'HS256');
    expect(header['kid'], 'petnote-local-hs256');
    expect(payload['household_id'], 'household-1');
    expect(payload['device_id'], 'device-1');
    expect(payload['role'], 'owner');
    expect(payload['iat'], 1780000000);
    expect(payload['exp'], 1780000900);
  });

  test('Postgres upload repository SQL 包含幂等与角色优先级保护', () {
    final source =
        File('lib/src/powersync_upload_repository.dart').readAsStringSync();

    expect(source, contains('ON CONFLICT (client_op_id) DO NOTHING'));
    expect(source, contains('excluded.role_priority >='));
    expect(source, contains("if (table == 'pet_photo_assets')"));
    expect(source, contains('pet_photo_assets requires pet_id'));
    expect(source, contains("'petId': petId"));
    expect(
      source,
      contains(
        'owner_device_id = CASE WHEN \$shouldApplyCondition THEN excluded.owner_device_id ELSE \$table.owner_device_id END',
      ),
    );
    expect(source, contains("'owner' => 20"));
    expect(source, contains("'pet' => 10"));
    expect(source, contains('unsupported powersync table'));
  });
}

PowerSyncJwtSigner _fixedSigner() {
  return PowerSyncJwtSigner(
    secret: 'test-secret',
    now: () => DateTime.fromMillisecondsSinceEpoch(1780000000000, isUtc: true),
  );
}

Map<String, dynamic> _decodeJwtPayload(String token) {
  final payload = token.split('.')[1];
  return jsonDecode(
    utf8.decode(base64Url.decode(base64.normalize(payload))),
  ) as Map<String, dynamic>;
}

Future<_HttpResponseBody> _postJson(
  HttpServer server,
  String path,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  final request =
      await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}$path'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  client.close();
  return _HttpResponseBody(response.statusCode, responseBody);
}

class _HttpResponseBody {
  const _HttpResponseBody(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _RecordingPowerSyncRepository implements PowerSyncUploadRepository {
  final List<PowerSyncUploadRequest> requests = <PowerSyncUploadRequest>[];

  @override
  bool get isConfigured => true;

  @override
  Future<PowerSyncUploadResult> applyUpload(
    PowerSyncUploadRequest request,
  ) async {
    requests.add(request);
    return const PowerSyncUploadResult(applied: 1, skipped: 0);
  }

  @override
  Future<void> close() async {}
}
