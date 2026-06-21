import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

typedef PowerSyncPostJson = Future<String> Function(
  Uri uri,
  Map<String, dynamic> body,
);

class PetNotePowerSyncConnector extends PowerSyncBackendConnector {
  PetNotePowerSyncConnector({
    required String? syncServerUrl,
    required String? householdId,
    required String? authToken,
    required String? deviceId,
    required String role,
    http.Client? client,
    PowerSyncPostJson? postJson,
    bool? closeClientOnDispose,
  })  : _baseUri = powerSyncBaseUriFromSyncServerUrl(syncServerUrl),
        _householdId = _normalize(householdId),
        _authToken = _normalize(authToken),
        _deviceId = _normalize(deviceId),
        _role = role,
        _client = client ?? (postJson == null ? http.Client() : null),
        _postJson = postJson,
        _ownsClient =
            closeClientOnDispose ?? (client == null && postJson == null);

  final Uri? _baseUri;
  final String? _householdId;
  final String? _authToken;
  final String? _deviceId;
  final String _role;
  final http.Client? _client;
  final PowerSyncPostJson? _postJson;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) {
      _client?.close();
    }
  }

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final baseUri = _baseUri;
    final body = _identityBody();
    if (baseUri == null || body == null) {
      return null;
    }
    final responseText = await _postJsonBody(
      baseUri.resolve('/powersync/credentials'),
      body,
    );
    final json = jsonDecode(responseText);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('invalid powersync credentials payload');
    }
    return PowerSyncCredentials.fromJson(json);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    while (true) {
      final transaction = await database.getNextCrudTransaction();
      if (transaction == null) {
        return;
      }
      await uploadOperations(
        transaction.crud.map((entry) => entry.toJson()).toList(growable: false),
      );
      await transaction.complete();
    }
  }

  Future<void> uploadOperations(List<Map<String, dynamic>> operations) async {
    if (operations.isEmpty) {
      return;
    }
    final baseUri = _baseUri;
    final body = buildUploadBody(operations);
    if (baseUri == null || body == null) {
      throw StateError('powersync identity is incomplete');
    }
    await _postJsonBody(baseUri.resolve('/powersync/upload'), body);
  }

  Map<String, dynamic>? buildUploadBody(
    List<Map<String, dynamic>> operations,
  ) {
    final identity = _identityBody();
    if (identity == null) {
      return null;
    }
    return {
      ...identity,
      'operations': operations,
    };
  }

  Map<String, dynamic>? _identityBody() {
    final householdId = _householdId;
    final authToken = _authToken;
    final deviceId = _deviceId;
    if (householdId == null || authToken == null || deviceId == null) {
      return null;
    }
    return {
      'householdId': householdId,
      'authToken': authToken,
      'deviceId': deviceId,
      'role': _role,
    };
  }

  Future<String> _postJsonBody(Uri uri, Map<String, dynamic> body) async {
    final postJson = _postJson;
    if (postJson != null) {
      return postJson(uri, body);
    }
    final client = _client;
    if (client == null) {
      throw StateError('powersync connector client is not available');
    }
    final response = await client.post(
      uri,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'powersync request failed: ${response.statusCode} ${response.body}',
      );
    }
    return response.body;
  }
}

Uri? powerSyncBaseUriFromSyncServerUrl(String? syncServerUrl) {
  final normalized = syncServerUrl?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final scheme = switch (uri.scheme) {
    'wss' => 'https',
    'ws' => 'http',
    'https' => 'https',
    'http' => 'http',
    _ => null,
  };
  if (scheme == null) {
    return null;
  }
  return uri.replace(scheme: scheme, path: '/', query: null, fragment: null);
}

String? _normalize(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
