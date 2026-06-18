import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server deployment documents and passes through rtc token env', () {
    final compose = File('server/docker-compose.yml').readAsStringSync();
    final serverReadme = File('server/README.md').readAsStringSync();
    final rootReadme = File('README.md').readAsStringSync();

    expect(compose, contains('ALICLOUD_RTC_APP_ID'));
    expect(compose, contains('ALICLOUD_RTC_APP_KEY'));
    expect(serverReadme, contains('POST /rtc/token'));
    expect(serverReadme, contains('singleToken'));
    expect(serverReadme, contains('ALICLOUD_RTC_APP_ID'));
    expect(serverReadme, contains('ALICLOUD_RTC_APP_KEY'));
    expect(rootReadme, contains('ALICLOUD_RTC_APP_ID'));
    expect(rootReadme, contains('ALICLOUD_RTC_APP_KEY'));
  });
}
