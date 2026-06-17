import 'package:flutter/foundation.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

class SyncFailureQueue {
  SyncFailureQueue({
    required this.transport,
    required this.failedCount,
    required this.lastError,
  });

  final SyncTransport transport;
  final ValueNotifier<int> failedCount;
  final ValueNotifier<Object?> lastError;

  final List<SyncMessage> _messages = <SyncMessage>[];

  bool get hasFailures => _messages.isNotEmpty;

  void sendOrQueue(SyncMessage message) {
    if (transport.state.value != SyncConnectionState.connected) {
      _messages.add(message);
      _refreshFailedCount();
      return;
    }
    try {
      transport.send(message);
    } on Object catch (error) {
      _messages.add(message);
      lastError.value = error;
      _refreshFailedCount();
    }
  }

  void retry() {
    if (_messages.isEmpty ||
        transport.state.value != SyncConnectionState.connected) {
      _refreshFailedCount();
      return;
    }
    final pending = List<SyncMessage>.from(_messages);
    _messages.clear();
    for (final message in pending) {
      try {
        transport.send(message);
      } on Object catch (error) {
        _messages.add(message);
        lastError.value = error;
      }
    }
    _refreshFailedCount();
  }

  void clear() {
    _messages.clear();
    _refreshFailedCount();
  }

  void dispose() {
    clear();
  }

  void _refreshFailedCount() {
    failedCount.value = _messages.length;
  }
}
