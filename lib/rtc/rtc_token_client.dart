import 'dart:convert';

import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:http/http.dart' as http;

enum RtcTokenRole {
  publisher,
  subscriber;
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
  final String role;
  final String token;
  final String singleToken;
  final String nonce;
  final int timestamp;
  final List<String> gslb;
  final int expiresAtMs;

  RtcJoinConfig toJoinConfig({required String remoteUserId}) {
    return RtcJoinConfig(
      appId: appId,
      channelId: channelId,
      userId: userId,
      remoteUserId: remoteUserId,
      role: role,
      token: token,
      singleToken: singleToken,
      nonce: nonce,
      timestamp: timestamp,
      gslb: gslb,
    );
  }
}

class RtcTokenClient {
  RtcTokenClient({
    required Uri baseUri,
    http.Client? client,
    Future<String> Function(Uri uri, Map<String, dynamic> body)? postJson,
    DateTime Function()? now,
    Duration cacheRefreshWindow = const Duration(seconds: 30),
    bool? closeClientOnDispose,
  })  : _baseUri = baseUri,
        _client = client ?? (postJson == null ? http.Client() : null),
        _ownsClient =
            closeClientOnDispose ?? (client == null && postJson == null),
        _postJson = postJson,
        _now = now,
        _cacheRefreshWindow = cacheRefreshWindow;

  final Uri _baseUri;
  final http.Client? _client;
  final bool _ownsClient;
  final Future<String> Function(Uri uri, Map<String, dynamic> body)? _postJson;
  final DateTime Function()? _now;
  final Duration _cacheRefreshWindow;
  final Map<_RtcTokenCacheKey, RtcTokenPayload> _cache =
      <_RtcTokenCacheKey, RtcTokenPayload>{};

  void dispose() {
    if (_ownsClient) {
      _client?.close();
    }
  }

  Future<RtcTokenPayload> issueToken({
    required String channelId,
    required String userId,
    required RtcTokenRole role,
    String? householdId,
    String? authToken,
  }) async {
    final normalizedHouseholdId = _normalizeOptional(householdId);
    final normalizedAuthToken = _normalizeOptional(authToken);
    final cacheKey = _RtcTokenCacheKey(
      channelId: channelId,
      userId: userId,
      role: role,
      householdId: normalizedHouseholdId,
      authToken: normalizedAuthToken,
    );
    final cached = _cache[cacheKey];
    if (cached != null && !_isExpiring(cached)) {
      return cached;
    }

    final uri = _baseUri.resolve('/rtc/token');
    final body = {
      'channelId': channelId,
      'userId': userId,
      'role': role.name,
      if (normalizedHouseholdId != null) 'householdId': normalizedHouseholdId,
      if (normalizedAuthToken != null) 'authToken': normalizedAuthToken,
    };
    final responseText =
        await (_postJson?.call(uri, body) ?? _defaultPostJson(uri, body));
    final json = jsonDecode(responseText);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('invalid rtc token payload');
    }
    final payload = RtcTokenPayload(
      appId: json['appId'] as String,
      channelId: json['channelId'] as String,
      userId: json['userId'] as String,
      role: json['role'] as String,
      token: json['token'] as String,
      singleToken: json['singleToken'] as String,
      nonce: json['nonce'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      gslb: List<String>.from(json['gslb'] as List<dynamic>),
      expiresAtMs: (json['expiresAtMs'] as num).toInt(),
    );
    _validateTokenPayload(
      payload: payload,
      channelId: channelId,
      userId: userId,
      role: role,
    );
    _cache[cacheKey] = payload;
    return payload;
  }

  Future<String> _defaultPostJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('rtc token client is not available');
    }
    final response = await client.post(
      uri,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'rtc token request failed: ${response.statusCode} ${response.body}',
      );
    }
    return response.body;
  }

  bool _isExpiring(RtcTokenPayload payload) {
    final nowMs = (_now ?? DateTime.now)().millisecondsSinceEpoch;
    return payload.expiresAtMs - nowMs <= _cacheRefreshWindow.inMilliseconds;
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _validateTokenPayload({
    required RtcTokenPayload payload,
    required String channelId,
    required String userId,
    required RtcTokenRole role,
  }) {
    if (payload.channelId != channelId ||
        payload.userId != userId ||
        payload.role != role.name) {
      throw const FormatException('rtc token payload does not match request');
    }
  }
}

class _RtcTokenCacheKey {
  const _RtcTokenCacheKey({
    required this.channelId,
    required this.userId,
    required this.role,
    required this.householdId,
    required this.authToken,
  });

  final String channelId;
  final String userId;
  final RtcTokenRole role;
  final String? householdId;
  final String? authToken;

  @override
  bool operator ==(Object other) {
    return other is _RtcTokenCacheKey &&
        other.channelId == channelId &&
        other.userId == userId &&
        other.role == role &&
        other.householdId == householdId &&
        other.authToken == authToken;
  }

  @override
  int get hashCode =>
      Object.hash(channelId, userId, role, householdId, authToken);
}
