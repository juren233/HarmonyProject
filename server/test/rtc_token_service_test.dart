import 'dart:convert';

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
        nonceFactory: () => 'AK-test-nonce');

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
    expect(token.nonce, 'AK-test-nonce');
    expect(token.timestamp, 1710003600);
    expect(token.gslb, ['https://rgslb.rtc.aliyuncs.com']);
    expect(
      token.token,
      'bec3093026403ef80106c9484d3d6ff503179a6953eeb7b28d3cd88279d802f4',
    );
    expect(token.singleToken, isA<String>());
    expect(token.singleToken, isNot(contains('fake-app-key-for-test')));
    expect(token.token, isNot(contains('fake-app-key-for-test')));
    final decodedSingleToken = jsonDecode(
      utf8.decode(base64Decode(token.singleToken)),
    ) as Map<String, dynamic>;
    expect(decodedSingleToken['appid'], 'nml2ycrp');
    expect(decodedSingleToken['channelid'], 'petnote-demo');
    expect(decodedSingleToken['userid'], 'owner-device');
    expect(decodedSingleToken['nonce'], 'AK-test-nonce');
    expect(decodedSingleToken['timestamp'], 1710003600);
    expect(decodedSingleToken['token'], token.token);
    expect(
        token.expiresAtMs, DateTime.utc(2024, 3, 9, 17).millisecondsSinceEpoch);
    expect(token.toJson().keys,
        containsAll(['singleToken', 'nonce', 'timestamp', 'gslb']));
  });

  test('Token 签名遵循官方字段且不受 nonce 影响', () {
    final baseService = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    },
        now: () => DateTime.utc(2024, 3, 9, 16),
        nonceFactory: () => 'AK-nonce-a');
    final changedNonceService = RtcTokenService.fromEnvironment(const {
      'ALICLOUD_RTC_APP_ID': 'nml2ycrp',
      'ALICLOUD_RTC_APP_KEY': 'fake-app-key-for-test',
    },
        now: () => DateTime.utc(2024, 3, 9, 16),
        nonceFactory: () => 'AK-nonce-b');

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
    expect(baseToken.token, changedNonceToken.token);
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
