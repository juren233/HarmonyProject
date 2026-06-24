import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

typedef SyncOutboxLoader = List<Map<String, dynamic>> Function();
typedef SyncOutboxSaver = Future<void> Function(
    List<Map<String, dynamic>> rows);

class SyncFailureQueue {
  SyncFailureQueue({
    required this.transport,
    required this.failedCount,
    required this.lastError,
    this.canSend,
    this.loadOutbox,
    this.saveOutbox,
    this.scopeKey,
    this.maxPendingMessages = 500,
    this.maxPendingBytes = 64 * 1024 * 1024,
    this.retryPollInterval = const Duration(seconds: 2),
    DateTime Function()? nowProvider,
  })  : _nowProvider = nowProvider ?? DateTime.now {
    _startRetryTimer();
  }

  final SyncTransport transport;
  final ValueNotifier<int> failedCount;
  final ValueNotifier<Object?> lastError;
  final bool Function()? canSend;
  final SyncOutboxLoader? loadOutbox;
  final SyncOutboxSaver? saveOutbox;
  final String? scopeKey;
  final int maxPendingMessages;
  final int maxPendingBytes;
  final Duration retryPollInterval;
  final DateTime Function() _nowProvider;

  final List<_QueuedSyncMessage> _messages = <_QueuedSyncMessage>[];
  Future<void> _persistQueue = Future<void>.value();
  Timer? _retryTimer;
  var _restored = false;

  bool get hasFailures => _messages.isNotEmpty;
  int get pendingCount => _messages.length;
  DateTime? get nextRetryAt {
    DateTime? next;
    for (final item in _messages) {
      final retryAt = item.nextRetryAt;
      if (retryAt == null) {
        return null;
      }
      if (next == null || retryAt.isBefore(next)) {
        next = retryAt;
      }
    }
    return next;
  }

  void restore() {
    if (_restored) {
      return;
    }
    _restored = true;
    final loader = loadOutbox;
    if (loader == null) {
      return;
    }
    final rows = loader();
    final restored = rows
        .map(_QueuedSyncMessage.fromJson)
        .whereType<_QueuedSyncMessage>()
        .where(_matchesScope)
        .toList(growable: false);
    _messages
      ..clear()
      ..addAll(restored);
    _refreshFailedCount();
    if (restored.length != rows.length) {
      _persist();
    }
  }

  void sendOrQueue(SyncMessage message) {
    if (!_isReadyToSend) {
      final item = _QueuedSyncMessage.create(
        message,
        _nowProvider(),
        scopeKey: scopeKey,
      );
      _queue(item);
      return;
    }
    try {
      transport.send(message);
    } on Object catch (error) {
      final item = _QueuedSyncMessage.create(
        message,
        _nowProvider(),
        scopeKey: scopeKey,
      ).failed(error, _nowProvider());
      if (!_queue(item)) {
        return;
      }
      lastError.value = error;
    }
  }

  void retry() {
    if (_messages.isEmpty || !_isReadyToSend) {
      _refreshFailedCount();
      return;
    }
    final now = _nowProvider();
    final pending = List<_QueuedSyncMessage>.from(_messages);
    _messages.clear();
    for (final item in pending) {
      if (item.nextRetryAt != null && item.nextRetryAt!.isAfter(now)) {
        _messages.add(item);
        continue;
      }
      try {
        transport.send(item.message);
      } on Object catch (error) {
        _messages.add(item.failed(error, now));
        lastError.value = error;
      }
    }
    _refreshFailedCount();
    _persist();
  }

  void clear() {
    _messages.clear();
    _refreshFailedCount();
    _persist();
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(retryPollInterval, (_) {
      if (_messages.isEmpty) {
        return;
      }
      final now = _nowProvider();
      final nextRetry = this.nextRetryAt;
      if (nextRetry != null && nextRetry.isAfter(now)) {
        return;
      }
      retry();
    });
  }

  Future<void> get persistIdle => _persistQueue;

  @visibleForTesting
  Future<void> get debugPersisted => _persistQueue;

  void _refreshFailedCount() {
    failedCount.value = _messages.length;
  }

  bool get _isReadyToSend {
    return transport.state.value == SyncConnectionState.connected &&
        (canSend?.call() ?? true);
  }

  bool _queue(_QueuedSyncMessage item) {
    final existingMessages = _withoutDuplicateBySyncId(item.message);
    if (!_canAdd(item, existingMessages)) {
      return false;
    }
    _messages
      ..clear()
      ..addAll(existingMessages)
      ..add(item);
    _refreshFailedCount();
    _persist();
    return true;
  }

  List<_QueuedSyncMessage> _withoutDuplicateBySyncId(SyncMessage message) {
    final syncId = message.payload['syncId'];
    if (syncId is! String || syncId.isEmpty) {
      return List<_QueuedSyncMessage>.from(_messages);
    }
    return _messages
        .where(
          (item) =>
              item.message.type != message.type ||
              item.message.payload['syncId'] != syncId,
        )
        .toList(growable: false);
  }

  bool _matchesScope(_QueuedSyncMessage item) {
    final currentScope = scopeKey;
    if (currentScope == null || currentScope.isEmpty) {
      return true;
    }
    return item.scopeKey == currentScope;
  }

  bool _canAdd(
    _QueuedSyncMessage item,
    List<_QueuedSyncMessage> existingMessages,
  ) {
    if (existingMessages.length >= maxPendingMessages) {
      lastError.value = SyncOutboxCapacityException(
        'sync outbox message limit reached: $maxPendingMessages',
      );
      _refreshFailedCount();
      return false;
    }
    final rows = [
      ...existingMessages.map((message) => message.toJson()),
      item.toJson(),
    ];
    final projectedBytes = utf8.encode(jsonEncode(rows)).length;
    if (projectedBytes > maxPendingBytes) {
      lastError.value = SyncOutboxCapacityException(
        'sync outbox byte limit reached: $maxPendingBytes',
      );
      _refreshFailedCount();
      return false;
    }
    return true;
  }

  void _persist() {
    final saver = saveOutbox;
    if (saver == null) {
      return;
    }
    final rows = _messages.map((item) => item.toJson()).toList();
    _persistQueue = _persistQueue
        .catchError((_) {})
        .then((_) => saver(rows))
        .catchError((Object error) {
      lastError.value = error;
    });
  }
}

class SyncOutboxCapacityException implements Exception {
  const SyncOutboxCapacityException(this.message);

  final String message;

  @override
  String toString() => 'SyncOutboxCapacityException($message)';
}

class _QueuedSyncMessage {
  _QueuedSyncMessage({
    required this.id,
    required this.message,
    required this.createdAt,
    this.attemptCount = 0,
    this.nextRetryAt,
    this.lastError,
    this.scopeKey,
  });

  final String id;
  final SyncMessage message;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final String? scopeKey;

  static _QueuedSyncMessage create(
    SyncMessage message,
    DateTime now, {
    String? scopeKey,
  }) {
    final id = '${now.microsecondsSinceEpoch}-${message.type}-'
        '${message.payload.hashCode}';
    return _QueuedSyncMessage(
      id: id,
      message: message,
      createdAt: now,
      scopeKey: scopeKey,
    );
  }

  static _QueuedSyncMessage? fromJson(Map<String, dynamic> json) {
    try {
      final type = json['type'];
      final payload = json['payload'];
      final createdAtMs = json['createdAtMs'];
      if (type is! String || payload is! Map || createdAtMs is! num) {
        return null;
      }
      final nextRetryAtMs = json['nextRetryAtMs'];
      return _QueuedSyncMessage(
        id: json['id'] as String? ??
            '${createdAtMs.toInt()}-$type-${payload.hashCode}',
        message: SyncMessage(type, Map<String, dynamic>.from(payload)),
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs.toInt(),
            isUtc: true),
        attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
        nextRetryAt: nextRetryAtMs is num
            ? DateTime.fromMillisecondsSinceEpoch(
                nextRetryAtMs.toInt(),
                isUtc: true,
              )
            : null,
        lastError: json['lastError'] as String?,
        scopeKey: json['scopeKey'] as String?,
      );
    } on Object {
      return null;
    }
  }

  _QueuedSyncMessage failed(Object error, DateTime now) {
    final nextAttempt = attemptCount + 1;
    final delaySeconds = switch (nextAttempt) {
      <= 1 => 1,
      2 => 2,
      3 => 4,
      4 => 8,
      5 => 16,
      _ => 30,
    };
    return _QueuedSyncMessage(
      id: id,
      message: message,
      createdAt: createdAt,
      attemptCount: nextAttempt,
      nextRetryAt: now.add(Duration(seconds: delaySeconds)),
      lastError: error.toString(),
      scopeKey: scopeKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': message.type,
        'payload': message.payload,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'attemptCount': attemptCount,
        if (nextRetryAt != null)
          'nextRetryAtMs': nextRetryAt!.millisecondsSinceEpoch,
        if (lastError != null) 'lastError': lastError,
        if (scopeKey != null && scopeKey!.isNotEmpty) 'scopeKey': scopeKey,
      };
}
