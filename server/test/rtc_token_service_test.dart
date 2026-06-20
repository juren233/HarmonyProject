import 'dart:convert';
import 'dart:io';

import 'package:petnote_sync_server/src/rtc_token_service.dart';
import 'package:test/test.dart';

void main() {
  test('缺少 ARTC 环境变量时禁用 Token 签发', () {
    final service = RtcTokenService.fromEnvironment(const {});

    expect(service.isConfigured, isFalse);
    expect(
      () => service.issueToken(
        channelId: 'petnote-demo',
        userId: 'owner-device',
        role: RtcUserRole.publisher,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('配置后返回 Token 且不泄露 AppKey', () {
    final service = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    },
        now: () => DateTime.utc(2024, 3, 9, 16),
        nonceFactory: () => 'AK-nonce-a',
        saltFactory: () => 123456789);

    final token = service.issueToken(
      channelId: 'petnote-demo',
      userId: 'owner-device',
      role: RtcUserRole.publisher,
    );

    expect(service.isConfigured, isTrue);
    expect(token.appId, 'nml2ycrp');
    expect(token.channelId, 'petnote-demo');
    expect(token.userId, 'owner-device');
    expect(token.role, RtcUserRole.publisher);
    expect(token.nonce, 'AK-nonce-a');
    expect(token.timestamp, 1710003600);
    expect(token.gslb, ['https://gslb.dingrtc.com']);
    expect(token.singleToken, isA<String>());
    expect(token.singleToken, token.token);
    expect(token.singleToken, isNot(contains('fake-app-key-for-test')));
    expect(token.token, isNot(contains('fake-app-key-for-test')));
    expect(token.token, startsWith('000'));
    final tokenBytes = zlib.decode(base64Decode(token.token.substring(3)));
    expect(tokenBytes.length, 512);
    expect(tokenBytes.sublist(36, 40), [0, 0, 0, 8]);
    expect(tokenBytes.sublist(40, 48), utf8.encode('nml2ycrp'));
    expect(
        token.expiresAtMs, DateTime.utc(2024, 3, 9, 17).millisecondsSinceEpoch);
    expect(token.toJson().keys,
        containsAll(['singleToken', 'nonce', 'timestamp', 'gslb']));
  });

  test('Token 签名与业务 nonce 解耦', () {
    final baseService = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    },
        now: () => DateTime.utc(2024, 3, 9, 16),
        nonceFactory: () => 'AK-nonce-a',
        saltFactory: () => 123456789);
    final changedNonceService = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    },
        now: () => DateTime.utc(2024, 3, 9, 16),
        nonceFactory: () => 'AK-nonce-b',
        saltFactory: () => 123456789);

    final baseToken = baseService.issueToken(
      channelId: 'petnote-demo',
      userId: 'owner-device',
      role: RtcUserRole.publisher,
    );
    final changedNonceToken = changedNonceService.issueToken(
      channelId: 'petnote-demo',
      userId: 'owner-device',
      role: RtcUserRole.publisher,
    );

    expect(baseToken.timestamp, changedNonceToken.timestamp);
    expect(baseToken.nonce, 'AK-nonce-a');
    expect(changedNonceToken.nonce, 'AK-nonce-b');
    expect(baseToken.token, changedNonceToken.token);
  });

  test('默认 nonce 使用 AK 前缀且不超过 64 字节', () {
    final service = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    });

    final token = service.issueToken(
      channelId: 'petnote-demo',
      userId: 'owner-device',
      role: RtcUserRole.publisher,
    );

    expect(token.nonce, startsWith('AK-'));
    expect(utf8.encode(token.nonce).length, lessThanOrEqualTo(64));
  });

  test('拒绝空房间或空用户', () {
    final service = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    });

    expect(
      () => service.issueToken(
        channelId: '',
        userId: 'owner-device',
        role: RtcUserRole.publisher,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.issueToken(
        channelId: 'petnote-demo',
        userId: '',
        role: RtcUserRole.publisher,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
