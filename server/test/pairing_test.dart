import 'dart:io';

import 'package:petnote_sync_server/src/household_store.dart';
import 'package:petnote_sync_server/src/pairing_service.dart';
import 'package:test/test.dart';

void main() {
  late HouseholdStore store;
  late PairingService pairing;

  setUp(() async {
    store = HouseholdStore(Directory.systemTemp.createTempSync('petnote_pair_'));
    await store.load();
    pairing = PairingService(store);
  });

  test('创建配对码并兑换建立 household 与设备', () {
    final created = pairing.createCode(
      existingHouseholdId: null,
      ownerDeviceId: 'owner-1',
      ownerDeviceName: '我的手机',
    );
    expect(created.code.length, 6);
    final joined = pairing.redeem(
      code: created.code,
      petDeviceId: 'pet-1',
      petDeviceName: '客厅平板',
    );
    expect(joined, isNotNull);
    expect(joined!.householdId, created.householdId);
    expect(joined.saltBase64, created.saltBase64);
    final household = store.household(created.householdId)!;
    expect(household.devices.keys, containsAll(['owner-1', 'pet-1']));
  });

  test('配对码只能兑换一次且过期失效', () {
    final created = pairing.createCode(
      existingHouseholdId: null,
      ownerDeviceId: 'owner-1',
      ownerDeviceName: '我的手机',
      now: DateTime.utc(2026, 1, 1),
    );
    expect(
      pairing.redeem(
        code: created.code,
        petDeviceId: 'p',
        petDeviceName: 'p',
        now: DateTime.utc(2026, 1, 1, 0, 6),
      ),
      isNull, // 超过 5 分钟
    );
  });

  test('快照与设备信息可持久化重载', () async {
    final created = pairing.createCode(
      existingHouseholdId: null,
      ownerDeviceId: 'o',
      ownerDeviceName: 'o',
    );
    store.household(created.householdId)!
      ..snapshotVersion = 7
      ..snapshotCiphertext = 'cipher';
    await store.flush();
    final reloaded = HouseholdStore(store.dataDirectory);
    await reloaded.load();
    expect(reloaded.household(created.householdId)!.snapshotVersion, 7);
    expect(reloaded.household(created.householdId)!.snapshotCiphertext, 'cipher');
  });
}
