import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    this.gslb = const ['https://gslb.dingrtc.com'],
    DateTime Function()? now,
    String Function()? nonceFactory,
    int Function()? saltFactory,
  })  : _appId = appId,
        _appKey = appKey,
        _now = now,
        _nonceFactory = nonceFactory,
        _saltFactory = saltFactory;

  factory RtcTokenService.fromEnvironment(
    Map<String, String> environment, {
    DateTime Function()? now,
    String Function()? nonceFactory,
    int Function()? saltFactory,
  }) {
    return RtcTokenService(
      appId: environment['ALICLOUD_RTC_APP_ID'],
      appKey: environment['ALICLOUD_RTC_APP_KEY'],
      now: now,
      nonceFactory: nonceFactory,
      saltFactory: saltFactory,
    );
  }

  final String? _appId;
  final String? _appKey;
  final Duration tokenTtl;
  final List<String> gslb;
  final DateTime Function()? _now;
  final String Function()? _nonceFactory;
  final int Function()? _saltFactory;

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
    final issueTimestamp = now.millisecondsSinceEpoch ~/ 1000;
    final timestamp = expiresAt.millisecondsSinceEpoch ~/ 1000;
    final nonce = (_nonceFactory ?? _randomNonce)();
    final token = _buildAppToken(
      appId: appId,
      appKey: appKey,
      channelId: normalizedChannelId,
      userId: normalizedUserId,
      issueTimestamp: issueTimestamp,
      salt: (_saltFactory ?? _randomSalt)(),
      expiresAtTimestamp: timestamp,
    );
    final singleToken = token;
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
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'AK-${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  }

  int _randomSalt() => Random.secure().nextInt(0x7fffffff) + 1;

  String _buildAppToken({
    required String appId,
    required String appKey,
    required String channelId,
    required String userId,
    required int issueTimestamp,
    required int salt,
    required int expiresAtTimestamp,
  }) {
    final signKey = _generateSignKey(appKey, issueTimestamp, salt);
    final body = _ByteWriter()
      ..writeString(appId)
      ..writeUint32(issueTimestamp)
      ..writeUint32(salt)
      ..writeUint32(expiresAtTimestamp)
      ..writeBytes(_packService(channelId: channelId, userId: userId))
      ..writeBytes(_packOptions());
    final bodyBytes = _fixedLengthBytes(body.toBytes());
    final signature = Hmac(sha256, signKey).convert(bodyBytes).bytes;
    final token = _ByteWriter()
      ..writeUint32(signature.length)
      ..writeBytes(signature)
      ..writeBytes(bodyBytes);
    final compressed = zlib.encode(_fixedLengthBytes(token.toBytes()));
    return '000${base64Encode(compressed)}';
  }

  List<int> _generateSignKey(String appKey, int issueTimestamp, int salt) {
    final signKey =
        Hmac(sha256, _uint32Bytes(issueTimestamp)).convert(utf8.encode(appKey)).bytes;
    return Hmac(sha256, _uint32Bytes(salt)).convert(signKey).bytes;
  }

  List<int> _packService({
    required String channelId,
    required String userId,
  }) {
    return (_ByteWriter()
          ..writeString(channelId)
          ..writeString(userId)
          ..writeBool(false))
        .toBytes();
  }

  List<int> _packOptions() {
    return (_ByteWriter()
          ..writeBool(true)
          ..writeUint32(0))
        .toBytes();
  }

  List<int> _uint32Bytes(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  Uint8List _fixedLengthBytes(Uint8List bytes) {
    final fixedLength = _nextMultiple(bytes.length, 256);
    if (fixedLength == bytes.length) {
      return bytes;
    }
    final padded = Uint8List(fixedLength);
    padded.setAll(0, bytes);
    return padded;
  }

  int _nextMultiple(int value, int baseValue) {
    if (baseValue <= 0 || value <= 0) {
      return 0;
    }
    var result = baseValue;
    while (result < value) {
      result *= 2;
    }
    return result;
  }
}

class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeBool(bool value) => _builder.add([value ? 1 : 0]);

  void writeUint32(int value) => _builder.add(_uint32Bytes(value));

  void writeString(String value) {
    final bytes = utf8.encode(value);
    writeUint32(bytes.length);
    _builder.add(bytes);
  }

  void writeBytes(List<int> bytes) => _builder.add(bytes);

  Uint8List toBytes() => _builder.takeBytes();

  List<int> _uint32Bytes(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}
