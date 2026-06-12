import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  test('连接后可收发消息，断开后自动重连', () async {
    final connections = <WebSocket>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connections.add(socket);
      socket.listen((raw) {
        final message = SyncMessage.decode(raw as String);
        if (message.type == SyncMessageTypes.hello) {
          socket.add(
            const SyncMessage(
              SyncMessageTypes.helloAck,
              {'snapshotVersion': 0},
            ).encode(),
          );
        }
      });
    });

    final client = SyncClient(
      url: 'ws://127.0.0.1:${server.port}/ws',
      reconnectBaseDelay: const Duration(milliseconds: 50),
    );
    final received = <SyncMessage>[];
    final subscription = client.messages.listen(received.add);

    await client.connect();
    client.send(
      const SyncMessage(SyncMessageTypes.hello, {
        'householdId': 'h',
        'deviceId': 'd',
        'role': 'pet',
        'deviceName': 'n',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(received.map((message) => message.type),
        contains(SyncMessageTypes.helloAck));
    expect(client.state.value, SyncConnectionState.connected);

    await connections.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(connections.length, greaterThan(1));

    await subscription.cancel();
    await client.disconnect();
    await server.close(force: true);
  });

  test('收到坏消息时通过 errors 暴露错误而不是静默吞掉', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add('bad-json');
    });

    final client = SyncClient(
      url: 'ws://127.0.0.1:${server.port}/ws',
      reconnectBaseDelay: const Duration(milliseconds: 50),
    );
    final errors = <Object>[];
    final subscription = client.errors.listen(errors.add);

    await client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(errors, isNotEmpty);
    await subscription.cancel();
    await client.disconnect();
    await server.close(force: true);
  });
}
