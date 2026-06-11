import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'server_app.dart';

/// 每条 WebSocket 连接一个会话。hello/pair 之后才进入已认证状态。
class SessionHandler {
  SessionHandler({required this.app, required this.channel});

  final SyncServerApp app;
  final WebSocketChannel channel;

  String? householdId;
  String? deviceId;

  void bind() {
    channel.stream.listen(_onData, onDone: _onDone, onError: (_) => _onDone());
  }

  void _onData(dynamic raw) {
    final SyncMessage message;
    try {
      message = SyncMessage.decode(raw as String);
    } on FormatException {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'bad message'}));
      return;
    }
    handle(message);
  }

  void handle(SyncMessage message) {
    switch (message.type) {
      case SyncMessageTypes.hello:
        _handleHello(message);
      default:
        _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'unsupported'}));
    }
  }

  void _handleHello(SyncMessage message) {
    final household = app.store.household(message.payload['householdId'] as String?);
    if (household == null) {
      _send(SyncMessage(SyncMessageTypes.pairError, {'message': 'unknown household'}));
      return;
    }
    householdId = household.id;
    deviceId = message.payload['deviceId'] as String;
    app.hub.register(householdId!, deviceId!, channel);
    _send(SyncMessage(SyncMessageTypes.helloAck, {'snapshotVersion': household.snapshotVersion}));
  }

  void _onDone() {
    if (householdId != null && deviceId != null) {
      app.hub.unregister(householdId!, deviceId!, channel);
    }
  }

  void _send(SyncMessage message) => channel.sink.add(message.encode());
}
