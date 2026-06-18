import 'dart:io';
import 'dart:convert';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:petnote_sync_server/src/household_store.dart';
import 'package:petnote_sync_server/src/rtc_token_service.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  late SyncServerApp app;
  late HttpServer server;

  setUp(() async {
    app = SyncServerApp(
        dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'));
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() async {
    await app.close();
    await server.close(force: true);
  });

  test('healthz 返回 ok', () async {
    final client = HttpClient();
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/healthz'));
    final response = await request.close();
    expect(response.statusCode, 200);
    client.close();
  });

  test('未配置 ARTC 时 Token 接口返回 503', () async {
    final client = HttpClient();
    final request = await client
        .postUrl(Uri.parse('http://127.0.0.1:${server.port}/rtc/token'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'channelId': 'petnote-demo',
      'userId': 'owner-device',
      'role': 'publisher',
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, 503);
    expect(body, contains('rtc not configured'));
    client.close();
  });

  test('配置 ARTC 后 Token 接口返回房间凭证且不泄露 AppKey', () async {
    await server.close(force: true);
    await app.close();
    app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'),
      rtcTokenService: RtcTokenService.fromEnvironment(const {
        'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
        'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
      }),
    );
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
    app.store.create('household-1', 'salt', 'auth-token')
      .devices['owner-device'] = HouseholdDevice(
      deviceId: 'owner-device',
      name: '主人手机',
    );

    final client = HttpClient();
    final request = await client
        .postUrl(Uri.parse('http://127.0.0.1:${server.port}/rtc/token'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'channelId': 'petnote-demo',
      'userId': 'owner-device',
      'role': 'publisher',
      'householdId': 'household-1',
      'authToken': 'auth-token',
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    expect(response.statusCode, 200);
    expect(json['appId'], 'nml2ycrp');
    expect(json['channelId'], 'petnote-demo');
    expect(json['userId'], 'owner-device');
    expect(json['role'], 'publisher');
    expect(json['token'], isA<String>());
    expect(json['token'] as String, isNot(contains('fake-app-key-for-test')));
    expect(json['singleToken'], isA<String>());
    expect(
        json['singleToken'] as String, isNot(contains('fake-app-key-for-test')));
    expect(json['nonce'], isA<String>());
    expect(json['timestamp'], isA<int>());
    expect(json['gslb'], isA<List<dynamic>>());
    expect(json['gslb'], isNotEmpty);
    expect(json['expiresAtMs'], isA<int>());
    client.close();
  });

  test('Token 接口拒绝缺字段请求', () async {
    await server.close(force: true);
    await app.close();
    app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'),
      rtcTokenService: RtcTokenService.fromEnvironment(const {
        'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
        'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
      }),
    );
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);

    final client = HttpClient();
    final request = await client
        .postUrl(Uri.parse('http://127.0.0.1:${server.port}/rtc/token'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'channelId': 'petnote-demo'}));
    final response = await request.close();

    expect(response.statusCode, 400);
    client.close();
  });

  test('Token 接口拒绝未认证请求', () async {
    await server.close(force: true);
    await app.close();
    app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'),
      rtcTokenService: RtcTokenService.fromEnvironment(const {
        'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
        'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
      }),
    );
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
    app.store.create('household-1', 'salt', 'auth-token');

    final client = HttpClient();
    final request = await client
        .postUrl(Uri.parse('http://127.0.0.1:${server.port}/rtc/token'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'channelId': 'petnote-demo',
      'userId': 'owner-device',
      'role': 'publisher',
      'householdId': 'household-1',
      'authToken': 'wrong-token',
    }));
    final response = await request.close();

    expect(response.statusCode, 401);
    client.close();
  });

  test('Token 接口拒绝非本 household 设备', () async {
    await server.close(force: true);
    await app.close();
    app = SyncServerApp(
      dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'),
      rtcTokenService: RtcTokenService.fromEnvironment(const {
        'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
        'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
      }),
    );
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
    app.store.create('household-1', 'salt', 'auth-token')
      .devices['known-device'] = HouseholdDevice(
      deviceId: 'known-device',
      name: '已配对设备',
    );

    final client = HttpClient();
    final request = await client
        .postUrl(Uri.parse('http://127.0.0.1:${server.port}/rtc/token'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'channelId': 'petnote-demo',
      'userId': 'owner-device',
      'role': 'publisher',
      'householdId': 'household-1',
      'authToken': 'auth-token',
    }));
    final response = await request.close();

    expect(response.statusCode, 403);
    client.close();
  });

  test('未知 household 的 hello 收到 pair_error', () async {
    final ws = IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}/ws');
    ws.sink.add(SyncMessage(SyncMessageTypes.hello, {
      'householdId': 'nope',
      'deviceId': 'd1',
      'role': 'pet',
      'deviceName': 'tablet',
    }).encode());
    final reply = SyncMessage.decode(await ws.stream.first as String);
    expect(reply.type, SyncMessageTypes.pairError);
    await ws.sink.close();
  });

  test('已有 household 的 hello 缺少 token 会拒绝', () async {
    final created = app.pairing.createCode(
      issuerDeviceId: 'owner-1',
      issuerDeviceName: '主人手机',
      issuerRole: 'owner',
    );
    final ws = IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}/ws');
    ws.sink.add(SyncMessage(SyncMessageTypes.hello, {
      'householdId': created.householdId,
      'deviceId': 'owner-1',
      'role': 'owner',
      'deviceName': '主人手机',
    }).encode());
    final reply = SyncMessage.decode(await ws.stream.first as String);
    expect(reply.type, SyncMessageTypes.pairError);
    expect(reply.payload['message'], 'auth failed');
    await ws.sink.close();
  });

  test('二进制帧与缺字段 hello 收到 pair_error 且连接不断开', () async {
    final ws = IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}/ws');
    final replies = <SyncMessage>[];
    final sub = ws.stream
        .listen((raw) => replies.add(SyncMessage.decode(raw as String)));

    ws.sink.add([0x01, 0x02, 0x03]); // 二进制帧
    ws.sink.add(SyncMessage(SyncMessageTypes.hello, {
      'householdId': 'h1',
      'role': 'pet',
      'deviceName': 'tablet',
      // deviceId 缺失
    }).encode());
    ws.sink.add(SyncMessage(SyncMessageTypes.hello, {
      'householdId': 123, // 非字符串 householdId
      'deviceId': 'd1',
    }).encode());

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(replies.length, 3);
    expect(replies.map((m) => m.type).toSet(), {SyncMessageTypes.pairError});
    await sub.cancel();
    await ws.sink.close();
  });
}
