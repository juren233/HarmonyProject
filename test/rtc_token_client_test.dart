import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_token_client.dart';

void main() {
  test('RtcTokenClient requests token and maps rtc join config', () async {
    late Map<String, dynamic> requestBody;
    final client = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        requestBody = body;
        expect(uri.toString(), 'https://sync.example.com/rtc/token');
        expect(body, {
          'channelId': 'call-1',
          'userId': 'owner-device',
          'role': 'publisher',
          'householdId': 'household-1',
          'authToken': 'auth-token',
        });
        return jsonEncode({
          'appId': 'nml2ycrp',
          'channelId': 'call-1',
          'userId': 'owner-device',
          'role': 'publisher',
          'token': 'token-value',
          'singleToken': 'single-token-value',
          'nonce': 'AK-nonce',
          'timestamp': 1710003600,
          'gslb': ['https://rgslb.rtc.aliyuncs.com'],
          'expiresAtMs': 1710003600000,
        });
      },
    );

    final token = await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
      householdId: 'household-1',
      authToken: 'auth-token',
    );

    expect(token.appId, 'nml2ycrp');
    expect(token.nonce, 'AK-nonce');
    expect(token.timestamp, 1710003600);
    expect(token.gslb, ['https://rgslb.rtc.aliyuncs.com']);
    expect(requestBody, containsPair('householdId', 'household-1'));
    expect(requestBody, containsPair('authToken', 'auth-token'));
    final joinConfig = token.toJoinConfig(remoteUserId: 'pet-device');
    expect(joinConfig, isA<RtcJoinConfig>());
    expect(joinConfig.remoteUserId, 'pet-device');
    expect(joinConfig.token, 'token-value');
    expect(joinConfig.singleToken, 'single-token-value');
  });

  test('RtcTokenClient reuses token until it is close to expiry', () async {
    var now = DateTime.utc(2024, 3, 9, 16);
    var requestCount = 0;
    final client = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      now: () => now,
      postJson: (uri, body) async {
        requestCount += 1;
        return jsonEncode({
          'appId': 'nml2ycrp',
          'channelId': body['channelId'],
          'userId': body['userId'],
          'role': body['role'],
          'token': 'token-$requestCount',
          'singleToken': 'single-token-$requestCount',
          'nonce': 'AK-nonce-$requestCount',
          'timestamp': 1710003600 + requestCount,
          'gslb': ['https://rgslb.rtc.aliyuncs.com'],
          'expiresAtMs': DateTime.utc(2024, 3, 9, 16, 1).millisecondsSinceEpoch,
        });
      },
    );

    final first = await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
    );
    final second = await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
    );

    expect(identical(first, second), isTrue);
    expect(requestCount, 1);

    now = DateTime.utc(2024, 3, 9, 16, 0, 31);
    final refreshed = await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
    );

    expect(refreshed.token, 'token-2');
    expect(requestCount, 2);
  });

  test('RtcTokenClient cache is scoped by channel, user, and role', () async {
    var requestCount = 0;
    final client = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      now: () => DateTime.utc(2024, 3, 9, 16),
      postJson: (uri, body) async {
        requestCount += 1;
        return jsonEncode({
          'appId': 'nml2ycrp',
          'channelId': body['channelId'],
          'userId': body['userId'],
          'role': body['role'],
          'token': 'token-$requestCount',
          'singleToken': 'single-token-$requestCount',
          'nonce': 'AK-nonce-$requestCount',
          'timestamp': 1710003600 + requestCount,
          'gslb': ['https://rgslb.rtc.aliyuncs.com'],
          'expiresAtMs': DateTime.utc(2024, 3, 9, 17).millisecondsSinceEpoch,
        });
      },
    );

    await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
    );
    await client.issueToken(
      channelId: 'call-2',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
    );
    await client.issueToken(
      channelId: 'call-1',
      userId: 'pet-device',
      role: RtcTokenRole.publisher,
    );
    await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.subscriber,
    );

    expect(requestCount, 4);
  });

  test('RtcTokenClient cache is scoped by household auth', () async {
    var requestCount = 0;
    final client = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      now: () => DateTime.utc(2024, 3, 9, 16),
      postJson: (uri, body) async {
        requestCount += 1;
        return jsonEncode({
          'appId': 'nml2ycrp',
          'channelId': body['channelId'],
          'userId': body['userId'],
          'role': body['role'],
          'token': 'token-$requestCount',
          'singleToken': 'single-token-$requestCount',
          'nonce': 'AK-nonce-$requestCount',
          'timestamp': 1710003600 + requestCount,
          'gslb': ['https://rgslb.rtc.aliyuncs.com'],
          'expiresAtMs': DateTime.utc(2024, 3, 9, 17).millisecondsSinceEpoch,
        });
      },
    );

    await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
      householdId: 'household-1',
      authToken: 'auth-token-1',
    );
    await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
      householdId: 'household-1',
      authToken: 'auth-token-2',
    );

    expect(requestCount, 2);
  });

  test('RtcTokenClient rejects mismatched payload and does not cache it',
      () async {
    var requestCount = 0;
    final client = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      postJson: (uri, body) async {
        requestCount += 1;
        if (requestCount == 1) {
          return jsonEncode({
            'appId': 'nml2ycrp',
            'channelId': 'wrong-channel',
            'userId': body['userId'],
            'role': body['role'],
            'token': 'token-bad',
            'singleToken': 'single-token-bad',
            'nonce': 'AK-bad',
            'timestamp': 1710003600,
            'gslb': ['https://rgslb.rtc.aliyuncs.com'],
            'expiresAtMs': 1710003600000,
          });
        }
        return jsonEncode({
          'appId': 'nml2ycrp',
          'channelId': body['channelId'],
          'userId': body['userId'],
          'role': body['role'],
          'token': 'token-good',
          'singleToken': 'single-token-good',
          'nonce': 'AK-good',
          'timestamp': 1710003601,
          'gslb': ['https://rgslb.rtc.aliyuncs.com'],
          'expiresAtMs': 1710003600000,
        });
      },
    );

    await expectLater(
      () => client.issueToken(
        channelId: 'call-1',
        userId: 'owner-device',
        role: RtcTokenRole.publisher,
      ),
      throwsFormatException,
    );

    final token = await client.issueToken(
      channelId: 'call-1',
      userId: 'owner-device',
      role: RtcTokenRole.publisher,
    );

    expect(token.token, 'token-good');
    expect(requestCount, 2);
  });

  test('RtcTokenClient dispose 按所有权关闭 HTTP client', () {
    final injectedClient = _CloseTrackingClient();
    final injectedTokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      client: injectedClient,
    );
    injectedTokenClient.dispose();

    expect(injectedClient.closeCount, 0);

    final ownedClient = _CloseTrackingClient();
    final ownedTokenClient = RtcTokenClient(
      baseUri: Uri.parse('https://sync.example.com'),
      client: ownedClient,
      closeClientOnDispose: true,
    );
    ownedTokenClient.dispose();

    expect(ownedClient.closeCount, 1);
  });
}

class _CloseTrackingClient extends http.BaseClient {
  var closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnimplementedError();
  }

  @override
  void close() {
    closeCount += 1;
  }
}
