import 'dart:io';

import 'package:petnote_sync_server/src/household_store.dart';
import 'package:petnote_sync_server/src/pairing_service.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  late HouseholdStore store;
  late PairingService pairing;

  setUp(() async {
    store =
        HouseholdStore(Directory.systemTemp.createTempSync('petnote_pair_'));
    await store.load();
    pairing = PairingService(store);
  });

  test('创建配对码并兑换建立 household 与设备', () {
    final created = pairing.createCode(
      existingHouseholdId: null,
      issuerDeviceId: 'owner-1',
      issuerDeviceName: '我的手机',
      issuerRole: 'owner',
    );
    expect(created.code.length, 4);
    expect(created.authToken, isNotEmpty);
    final joined = pairing.redeem(
      code: created.code,
      joiningDeviceId: 'pet-1',
      joiningDeviceName: '客厅平板',
      joiningRole: 'pet',
    );
    expect(joined, isNotNull);
    expect(joined!.householdId, created.householdId);
    expect(joined.saltBase64, created.saltBase64);
    expect(joined.authToken, created.authToken);
    final household = store.household(created.householdId)!;
    expect(household.devices.keys, containsAll(['owner-1', 'pet-1']));
  });

  test('配对码只能兑换一次且过期失效', () {
    final created = pairing.createCode(
      existingHouseholdId: null,
      issuerDeviceId: 'owner-1',
      issuerDeviceName: '我的手机',
      issuerRole: 'owner',
      now: DateTime.utc(2026, 1, 1),
    );
    expect(
      pairing.redeem(
        code: created.code,
        joiningDeviceId: 'p',
        joiningDeviceName: 'p',
        joiningRole: 'pet',
        now: DateTime.utc(2026, 1, 1, 0, 6),
      ),
      isNull, // 超过 5 分钟
    );
  });

  test('设备与同步账本可持久化重载且旧业务字段会迁移到账本', () async {
    final file = File('${store.dataDirectory.path}/households.json');
    await file.writeAsString('''
{"households":{"house-1":{"id":"house-1","saltBase64":"salt","authToken":"token","snapshotVersion":7,"snapshotCiphertext":"legacy-cipher","devices":{"o":{"deviceId":"o","name":"o","role":"owner"}},"pendingActions":[{"actionId":"legacy-action","ciphertext":"legacy-action-cipher"}],"completedActions":{"todo:todo-1":{"actionId":"done-1","ciphertext":"done-cipher","kind":"markDone","sourceType":"todo","itemId":"todo-1","syncId":"sync-1","originDeviceId":"o"}},"syncEvents":{"sync-1":{"syncId":"sync-1","originDeviceId":"o","messageType":"action","payload":{"actionId":"done-1","ciphertext":"done-cipher","kind":"markDone","sourceType":"todo","itemId":"todo-1","syncId":"sync-1","originDeviceId":"o"},"receivedByDeviceIds":["o"]}}}}}
''');
    final reloaded = HouseholdStore(store.dataDirectory);
    await reloaded.load();
    await reloaded.flush();
    final household = reloaded.household('house-1')!;
    expect(household.devices.keys, contains('o'));
    expect(household.completedActions['todo:todo-1']?['ciphertext'],
        'done-cipher');
    expect(
        household.syncEvents['sync-1']?.payload['ciphertext'], 'done-cipher');
    expect(household.syncEvents['sync-1']?.receivedByDeviceIds, {'o'});
    expect(household.syncEvents['sync-1']?.serverSeq, greaterThan(0));
    expect(household.syncEvents['sync-1']?.payload['serverSeq'],
        household.syncEvents['sync-1']?.serverSeq);
    expect(
      household.syncEvents.values.any((event) =>
          event.messageType == SyncMessageTypes.snapshot &&
          event.payload['ciphertext'] == 'legacy-cipher' &&
          event.payload['version'] == 7 &&
          event.serverSeq > 0 &&
          event.payload['serverSeq'] == event.serverSeq),
      isTrue,
    );
    expect(
      household.syncEvents.values.any((event) =>
          event.messageType == SyncMessageTypes.action &&
          event.payload['actionId'] == 'legacy-action' &&
          event.payload['ciphertext'] == 'legacy-action-cipher' &&
          event.serverSeq > 0 &&
          event.payload['serverSeq'] == event.serverSeq),
      isTrue,
    );
    expect(
        household.nextServerSeq,
        greaterThan(household.syncEvents.values
            .map((event) => event.serverSeq)
            .reduce((a, b) => a > b ? a : b)));
    final persisted = await file.readAsString();
    expect(persisted, contains('"role":"owner"'));
    expect(persisted, isNot(contains('snapshotCiphertext')));
    expect(persisted, isNot(contains('pendingActions')));
    expect(persisted, contains('legacy-cipher'));
    expect(persisted, contains('legacy-action-cipher'));
    expect(persisted, contains('completedActions'));
    expect(persisted, contains('syncEvents'));
  });

  test('旧 household 存储缺少 authToken 时加载后自动补齐', () async {
    final file = File('${store.dataDirectory.path}/households.json');
    await file.writeAsString('''
{"households":{"house-legacy":{"id":"house-legacy","saltBase64":"salt","devices":{},"pendingActions":[]}}}
''');
    final reloaded = HouseholdStore(store.dataDirectory);

    await reloaded.load();

    expect(reloaded.household('house-legacy')!.authToken, isNotEmpty);
  });

  test('加载时会保留已落盘去重索引', () async {
    final file = File('${store.dataDirectory.path}/households.json');
    await file.writeAsString('''
{"households":{"house-1":{"id":"house-1","saltBase64":"salt","authToken":"token","devices":{"o":{"deviceId":"o","name":"o"}},"syncEvents":{"live-action-sync":{"syncId":"live-action-sync","originDeviceId":"o","messageType":"action","payload":{"actionId":"live-action","ciphertext":"action-cipher","kind":"markDone","sourceType":"todo","itemId":"todo-1","syncId":"live-action-sync","originDeviceId":"o"},"receivedByDeviceIds":[]},"live-mutation-sync":{"syncId":"live-mutation-sync","originDeviceId":"o","messageType":"mutation","payload":{"mutationId":"live-mutation","ciphertext":"mutation-cipher","entityType":"todo","entityId":"todo-1","kind":"upsert","syncId":"live-mutation-sync","originDeviceId":"o"},"receivedByDeviceIds":[]}},"actionSyncEventIds":{"live-action":"live-action-sync","stale-action":"missing-sync","wrong-action":"live-mutation-sync"},"mutationSyncEventIds":{"live-mutation":"live-mutation-sync","stale-mutation":"missing-sync","wrong-mutation":"live-action-sync"}}}}
''');
    final reloaded = HouseholdStore(store.dataDirectory);

    await reloaded.load();

    final household = reloaded.household('house-1')!;
    expect(household.actionSyncEventIds, {
      'live-action': 'live-action-sync',
      'stale-action': 'missing-sync',
    });
    expect(
      household.mutationSyncEventIds,
      {
        'live-mutation': 'live-mutation-sync',
        'stale-mutation': 'missing-sync',
      },
    );
  });

  test('加载时会从同步事件回填缺失的去重索引', () async {
    final file = File('${store.dataDirectory.path}/households.json');
    await file.writeAsString('''
{"households":{"house-1":{"id":"house-1","saltBase64":"salt","authToken":"token","devices":{"o":{"deviceId":"o","name":"o"}},"syncEvents":{"live-action-sync":{"syncId":"live-action-sync","originDeviceId":"o","messageType":"action","payload":{"actionId":"live-action","ciphertext":"action-cipher","kind":"markDone","sourceType":"todo","itemId":"todo-1","syncId":"live-action-sync","originDeviceId":"o"},"receivedByDeviceIds":[]},"live-mutation-sync":{"syncId":"live-mutation-sync","originDeviceId":"o","messageType":"mutation","payload":{"mutationId":"live-mutation","ciphertext":"mutation-cipher","entityType":"todo","entityId":"todo-1","kind":"upsert","syncId":"live-mutation-sync","originDeviceId":"o"},"receivedByDeviceIds":[]}},"actionSyncEventIds":{},"mutationSyncEventIds":{}}}}
''');
    final reloaded = HouseholdStore(store.dataDirectory);

    await reloaded.load();

    final household = reloaded.household('house-1')!;
    expect(household.actionSyncEventIds, {'live-action': 'live-action-sync'});
    expect(
      household.mutationSyncEventIds,
      {'live-mutation': 'live-mutation-sync'},
    );
  });
}
