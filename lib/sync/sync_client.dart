import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class SyncClient implements SyncTransport {
  SyncClient({
    required this.url,
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 60),
  });

  final String url;
  final Duration reconnectBaseDelay;
  final Duration maxReconnectDelay;

  @override
  final ValueNotifier<SyncConnectionState> state =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.disconnected);

  final StreamController<SyncMessage> _messages =
      StreamController<SyncMessage>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final List<String> _outbox = <String>[];

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  var _retryCount = 0;
  var _shouldReconnect = false;
  var _disposed = false;

  @override
  Stream<SyncMessage> get messages => _messages.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('SyncClient disposed');
    }
    if (state.value == SyncConnectionState.connecting ||
        state.value == SyncConnectionState.connected) {
      return;
    }
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    state.value = SyncConnectionState.connecting;
    try {
      final socket = await WebSocket.connect(url);
      socket.pingInterval = const Duration(seconds: 30);
      _socket = socket;
      _retryCount = 0;
      state.value = SyncConnectionState.connected;
      for (final pending in _outbox) {
        socket.add(pending);
      }
      _outbox.clear();
      await _socketSubscription?.cancel();
      _socketSubscription = socket.listen(
        _handleRawMessage,
        onDone: _scheduleReconnect,
        onError: (Object error, StackTrace stackTrace) {
          _errors.add(error);
          _scheduleReconnect();
        },
      );
    } catch (error) {
      _errors.add(error);
      _scheduleReconnect();
      rethrow;
    }
  }

  @override
  void send(SyncMessage message) {
    final encoded = message.encode();
    final socket = _socket;
    if (state.value == SyncConnectionState.connected && socket != null) {
      socket.add(encoded);
      return;
    }
    _outbox.add(encoded);
  }

  void _handleRawMessage(dynamic raw) {
    if (raw is! String) {
      _errors
          .add(FormatException('invalid sync frame type: ${raw.runtimeType}'));
      return;
    }
    try {
      _messages.add(SyncMessage.decode(raw));
    } on Object catch (error) {
      _errors.add(error);
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _disposed) {
      return;
    }
    _socket = null;
    state.value = SyncConnectionState.disconnected;
    final exponent = min(_retryCount, 6);
    final delayMs = min(
      reconnectBaseDelay.inMilliseconds * pow(2, exponent).toInt(),
      maxReconnectDelay.inMilliseconds,
    );
    _retryCount += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      unawaited(connect());
    });
  }

  @override
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    state.value = SyncConnectionState.disconnected;
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _messages.close();
    await _errors.close();
    state.dispose();
  }
}
