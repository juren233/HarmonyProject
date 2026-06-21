import 'dart:convert';

import 'package:crypto/crypto.dart';

class PowerSyncJwtSigner {
  const PowerSyncJwtSigner({
    required this.secret,
    this.audience = 'powersync',
    this.issuer = 'petnote-sync',
    this.expiresIn = const Duration(minutes: 15),
    this.now,
  });

  final String secret;
  final String audience;
  final String issuer;
  final Duration expiresIn;
  final DateTime Function()? now;

  bool get isConfigured => secret.trim().isNotEmpty;

  PowerSyncSignedToken sign({
    required String householdId,
    required String deviceId,
    required String role,
  }) {
    if (!isConfigured) {
      throw StateError('powersync jwt secret not configured');
    }
    final issuedAt = (now ?? DateTime.now)().toUtc();
    final expiresAt = issuedAt.add(expiresIn);
    final header = <String, dynamic>{
      'alg': 'HS256',
      'typ': 'JWT',
      'kid': 'petnote-local-hs256',
    };
    final payload = <String, dynamic>{
      'iss': issuer,
      'aud': audience,
      'sub': deviceId,
      'household_id': householdId,
      'device_id': deviceId,
      'role': role,
      'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
      'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
    };
    final signingInput = '${_base64UrlJson(header)}.${_base64UrlJson(payload)}';
    final signature = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(signingInput))
        .bytes;
    return PowerSyncSignedToken(
      token: '$signingInput.${_base64UrlNoPadding(signature)}',
      expiresAt: expiresAt,
    );
  }

  static PowerSyncJwtSigner fromEnvironment(Map<String, String> env) {
    return PowerSyncJwtSigner(secret: env['POWERSYNC_JWT_SECRET'] ?? '');
  }
}

class PowerSyncSignedToken {
  const PowerSyncSignedToken({
    required this.token,
    required this.expiresAt,
  });

  final String token;
  final DateTime expiresAt;
}

String _base64UrlJson(Map<String, dynamic> value) {
  return _base64UrlNoPadding(utf8.encode(jsonEncode(value)));
}

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
