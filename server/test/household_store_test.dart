import 'dart:io';

import 'package:petnote_sync_server/src/household_store.dart';
import 'package:test/test.dart';

void main() {
  test('并发 flush 后写出的 households.json 可重新 load', () async {
    final directory =
        Directory.systemTemp.createTempSync('petnote_household_store_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final store = HouseholdStore(directory);
    final household = store.create('house-1', 'salt', 'auth-token');
    household.devices['owner-1'] = HouseholdDevice(
      deviceId: 'owner-1',
      name: '主人手机',
      role: 'owner',
      lastSeenMs: 100,
    );

    await Future.wait([
      store.flush(),
      store.flush(),
      store.flush(),
    ]);

    final reloaded = HouseholdStore(directory);
    await reloaded.load();

    expect(reloaded.household('house-1')?.authToken, 'auth-token');
    expect(reloaded.household('house-1')?.devices['owner-1']?.lastSeenMs, 100);
  });
}
