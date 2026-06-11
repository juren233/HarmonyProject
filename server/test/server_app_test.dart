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
}
