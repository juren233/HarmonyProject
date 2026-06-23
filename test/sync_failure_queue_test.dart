import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/sync/sync_failure_queue.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

void main() {
  test('持久化保存按队列顺序串行执行，clear 不会被旧写入覆盖', () async {
    final transport = _FakeSyncTransport()
      ..stateNotifier.value = SyncConnectionState.disconnected;
    final failedCount = ValueNotifier<int>(0);
    final lastError = ValueNotifier<Object?>(null);
    var persisted = <Map<String, dynamic>>[];
    final queue = SyncFailureQueue(
      transport: transport,
      failedCount: failedCount,
      lastError: lastError,
      saveOutbox: (rows) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        persisted = rows;
      },
    );

    queue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.snapshotRequest, {
        'dataPolicy': 'merge',
      }),
    );
    queue.clear();
    await queue.debugPersisted;

    expect(failedCount.value, 0);
    expect(persisted, isEmpty);
  });

  test('恢复 durable outbox 时过滤其他 household 的旧消息', () async {
    final transport = _FakeSyncTransport()
      ..stateNotifier.value = SyncConnectionState.disconnected;
    final failedCount = ValueNotifier<int>(0);
    final lastError = ValueNotifier<Object?>(null);
    var persisted = <Map<String, dynamic>>[];
    final rows = <Map<String, dynamic>>[
      _outboxRow(scopeKey: 'old-house'),
      _outboxRow(scopeKey: 'new-house'),
    ];
    final queue = SyncFailureQueue(
      transport: transport,
      failedCount: failedCount,
      lastError: lastError,
      scopeKey: 'new-house',
      loadOutbox: () => rows,
      saveOutbox: (nextRows) async {
        persisted = nextRows;
      },
    );

    queue.restore();
    await queue.debugPersisted;

    expect(failedCount.value, 1);
    expect(persisted, hasLength(1));
    expect(persisted.single['scopeKey'], 'new-house');
  });

  test('达到消息数量上限时拒绝继续入队并暴露容量错误', () async {
    final transport = _FakeSyncTransport()
      ..stateNotifier.value = SyncConnectionState.disconnected;
    final failedCount = ValueNotifier<int>(0);
    final lastError = ValueNotifier<Object?>(null);
    var persisted = <Map<String, dynamic>>[];
    final queue = SyncFailureQueue(
      transport: transport,
      failedCount: failedCount,
      lastError: lastError,
      maxPendingMessages: 1,
      saveOutbox: (rows) async {
        persisted = rows;
      },
    );

    queue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.snapshotRequest, {
        'dataPolicy': 'merge',
      }),
    );
    queue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.devicesRequest, {}),
    );
    await queue.debugPersisted;

    expect(failedCount.value, 1);
    expect(lastError.value, isA<SyncOutboxCapacityException>());
    expect(persisted, hasLength(1));
    expect(persisted.single['type'], SyncMessageTypes.snapshotRequest);
  });

  test('达到字节上限时拒绝入队并保留已有队列', () async {
    final transport = _FakeSyncTransport()
      ..stateNotifier.value = SyncConnectionState.disconnected;
    final failedCount = ValueNotifier<int>(0);
    final lastError = ValueNotifier<Object?>(null);
    var persisted = <Map<String, dynamic>>[];
    final queue = SyncFailureQueue(
      transport: transport,
      failedCount: failedCount,
      lastError: lastError,
      maxPendingBytes: 1,
      saveOutbox: (rows) async {
        persisted = rows;
      },
    );

    queue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.snapshotRequest, {
        'dataPolicy': 'merge',
      }),
    );
    await queue.debugPersisted;

    expect(failedCount.value, 0);
    expect(lastError.value, isA<SyncOutboxCapacityException>());
    expect(persisted, isEmpty);
  });

  test('字节上限按 UTF-8 持久化体积计算', () async {
    final now = DateTime.utc(2026, 6, 23, 12);
    const message = SyncMessage(SyncMessageTypes.snapshotRequest, {
      'dataPolicy': 'merge',
      'note': '同步🐶资料',
    });
    var persisted = <Map<String, dynamic>>[];

    final probeQueue = SyncFailureQueue(
      transport: _FakeSyncTransport(),
      failedCount: ValueNotifier<int>(0),
      lastError: ValueNotifier<Object?>(null),
      maxPendingBytes: 1024 * 1024,
      nowProvider: () => now,
      saveOutbox: (rows) async {
        persisted = rows;
      },
    );
    probeQueue.sendOrQueue(message);
    await probeQueue.debugPersisted;

    final encoded = jsonEncode(persisted);
    final codeUnitLimit = encoded.length;
    expect(utf8.encode(encoded).length, greaterThan(codeUnitLimit));

    final failedCount = ValueNotifier<int>(0);
    final lastError = ValueNotifier<Object?>(null);
    persisted = <Map<String, dynamic>>[];
    final queue = SyncFailureQueue(
      transport: _FakeSyncTransport(),
      failedCount: failedCount,
      lastError: lastError,
      maxPendingBytes: codeUnitLimit,
      nowProvider: () => now,
      saveOutbox: (rows) async {
        persisted = rows;
      },
    );

    queue.sendOrQueue(message);
    await queue.debugPersisted;

    expect(failedCount.value, 0);
    expect(lastError.value, isA<SyncOutboxCapacityException>());
    expect(persisted, isEmpty);
  });

  test('同 syncId 替换消息超限时保留既有队列', () async {
    final transport = _FakeSyncTransport()
      ..stateNotifier.value = SyncConnectionState.disconnected;
    final failedCount = ValueNotifier<int>(0);
    final lastError = ValueNotifier<Object?>(null);
    var persisted = <Map<String, dynamic>>[];
    final queue = SyncFailureQueue(
      transport: transport,
      failedCount: failedCount,
      lastError: lastError,
      maxPendingBytes: 400,
      saveOutbox: (rows) async {
        persisted = rows;
      },
    );

    queue.sendOrQueue(
      const SyncMessage(SyncMessageTypes.snapshotRequest, {
        'syncId': 'same-snapshot',
        'dataPolicy': 'merge',
      }),
    );
    await queue.debugPersisted;
    expect(persisted, hasLength(1));

    queue.sendOrQueue(
      SyncMessage(SyncMessageTypes.snapshotRequest, {
        'syncId': 'same-snapshot',
        'dataPolicy': 'merge',
        'note': List.filled(80, '同步🐶资料').join(),
      }),
    );
    await queue.debugPersisted;

    expect(failedCount.value, 1);
    expect(lastError.value, isA<SyncOutboxCapacityException>());
    expect(persisted, hasLength(1));
    expect(persisted.single['payload'], {
      'syncId': 'same-snapshot',
      'dataPolicy': 'merge',
    });
  });
}

Map<String, dynamic> _outboxRow({required String scopeKey}) {
  return {
    'id': '$scopeKey-snapshot-request',
    'type': SyncMessageTypes.snapshotRequest,
    'payload': {'dataPolicy': 'merge'},
    'createdAtMs': DateTime.utc(2026).millisecondsSinceEpoch,
    'scopeKey': scopeKey,
  };
}

class _FakeSyncTransport implements SyncTransport {
  final stateNotifier =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.disconnected);
  final messagesController = StreamController<SyncMessage>.broadcast();
  final errorsController = StreamController<Object>.broadcast();

  @override
  Stream<Object> get errors => errorsController.stream;

  @override
  Stream<SyncMessage> get messages => messagesController.stream;

  @override
  ValueListenable<SyncConnectionState> get state => stateNotifier;

  @override
  Future<void> connect() async {
    stateNotifier.value = SyncConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    stateNotifier.value = SyncConnectionState.disconnected;
  }

  @override
  void send(SyncMessage message) {}
}
