import 'dart:io';

import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:petnote_sync_server/src/server_app.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  late SyncServerApp app;
  late HttpServer server;

  setUp(() async {
    app = SyncServerApp(dataDirectory: Directory.systemTemp.createTempSync('petnote_srv_'));
    server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() async {
    await app.close();
    await server.close(force: true);
  });

  test('healthz 返回 ok', () async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/healthz'));
    final response = await request.close();
    expect(response.statusCode, 200);
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

  test('二进制帧与缺字段 hello 收到 pair_error 且连接不断开', () async {
    final ws = IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}/ws');
    final replies = <SyncMessage>[];
    final sub = ws.stream.listen((raw) => replies.add(SyncMessage.decode(raw as String)));

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
