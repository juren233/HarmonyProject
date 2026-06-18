import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum RtcUserRole {
  publisher,
  subscriber;

  static RtcUserRole parse(String value) {
    return RtcUserRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => throw const FormatException('invalid rtc role'),
    );
  }
}

class RtcTokenPayload {
  const RtcTokenPayload({
    required this.appId,
    required this.channelId,
    required this.userId,
    required this.role,
    required this.token,
    required this.singleToken,
    required this.nonce,
    required this.timestamp,
    required this.gslb,
    required this.expiresAtMs,
  });

  final String appId;
  final String channelId;
  final String userId;
  final RtcUserRole role;
  final String token;
  final String singleToken;
  final String nonce;
  final int timestamp;
  final List<String> gslb;
  final int expiresAtMs;

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'channelId': channelId,
        'userId': userId,
        'role': role.name,
        'token': token,
        'singleToken': singleToken,
        'nonce': nonce,
        'timestamp': timestamp,
        'gslb': gslb,
        'expiresAtMs': expiresAtMs,
      };
}

class RtcTokenService {
  const RtcTokenService({
    required String? appId,
    required String? appKey,
    this.tokenTtl = const Duration(hours: 1),
    this.gslb = const ['https://rgslb.rtc.aliyuncs.com'],
    DateTime Function()? now,
    String Function()? nonceFactory,
  })  : _appId = appId,
        _appKey = appKey,
        _now = now,
        _nonceFactory = nonceFactory;

  factory RtcTokenService.fromEnvironment(
    Map<String, String> environment, {
    DateTime Function()? now,
    String Function()? nonceFactory,
  }) {
    return RtcTokenService(
      appId: environment['ALICLOUD_RTC_APP_ID'],
      appKey: environment['ALICLOUD_RTC_APP_KEY'],
      now: now,
      nonceFactory: nonceFactory,
    );
  }

  final String? _appId;
  final String? _appKey;
  final Duration tokenTtl;
  final List<String> gslb;
  final DateTime Function()? _now;
  final String Function()? _nonceFactory;

  bool get isConfigured =>
      (_appId?.trim().isNotEmpty ?? false) &&
      (_appKey?.trim().isNotEmpty ?? false);

  RtcTokenPayload issueToken({
    required String channelId,
    required String userId,
    required RtcUserRole role,
  }) {
    if (!isConfigured) {
      throw StateError('rtc not configured');
    }
    final normalizedChannelId = channelId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedChannelId.isEmpty || normalizedUserId.isEmpty) {
      throw const FormatException('invalid rtc token request');
    }
    final appId = _appId!.trim();
    final appKey = _appKey!.trim();
    final now = (_now ?? DateTime.now)().toUtc();
    final expiresAt = now.add(tokenTtl);
    final timestamp = expiresAt.millisecondsSinceEpoch ~/ 1000;
    final nonce = (_nonceFactory ?? _randomNonce)();
    final token = sha256
        .convert(
            '$appId$appKey$normalizedChannelId$normalizedUserId$nonce$timestamp'
                .codeUnits)
        .toString();
    final singleToken = base64Encode(utf8.encode(jsonEncode({
      'appid': appId,
      'channelid': normalizedChannelId,
      'userid': normalizedUserId,
      'nonce': nonce,
      'timestamp': timestamp,
      'token': token,
    })));
    return RtcTokenPayload(
      appId: appId,
      channelId: normalizedChannelId,
      userId: normalizedUserId,
      role: role,
      token: token,
      singleToken: singleToken,
      nonce: nonce,
      timestamp: timestamp,
      gslb: gslb,
      expiresAtMs: expiresAt.millisecondsSinceEpoch,
    );
  }

  String _randomNonce() {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    final random = Random.secure();
    return List.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
