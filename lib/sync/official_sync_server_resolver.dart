import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:petnote/state/app_settings_controller.dart';

typedef OfficialServerConfigFetcher = Future<String> Function(Uri uri);

class OfficialSyncServerResolver {
  OfficialSyncServerResolver({
    Uri? configUri,
    OfficialServerConfigFetcher? fetcher,
    this.timeout = const Duration(seconds: 6),
  })  : configUri = configUri ?? Uri.parse(defaultConfigUrl),
        _fetcher = fetcher;

  static const String defaultConfigUrl =
      'https://petnote-server.juren233.top/server';

  final Uri configUri;
  final OfficialServerConfigFetcher? _fetcher;
  final Duration timeout;

  Future<String> resolve() async {
    try {
      final body = await (_fetcher ?? _fetchFromNetwork)(configUri);
      return normalizeSyncServerUrl(_extractServerValue(body));
    } on OfficialSyncServerException {
      rethrow;
    } on Object catch (error) {
      throw OfficialSyncServerException('获取官方服务器失败：$error');
    }
  }

  Future<String> _fetchFromNetwork(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw OfficialSyncServerException(
          '官方服务器配置返回 ${response.statusCode}',
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}

Future<String?> resolveConfiguredSyncServerUrl({
  required AppSettingsController settings,
  required OfficialSyncServerResolver officialResolver,
}) async {
  if (settings.syncServerMode == SyncServerMode.custom) {
    final configuredUrl = settings.syncServerUrl;
    if (configuredUrl == null) {
      return null;
    }
    final normalizedUrl = normalizeSyncServerUrl(configuredUrl);
    if (normalizedUrl != configuredUrl) {
      await settings.setSyncServerUrl(normalizedUrl);
    }
    return normalizedUrl;
  }
  try {
    final serverUrl = await officialResolver.resolve();
    await settings.setSyncServerUrl(serverUrl);
    return serverUrl;
  } on OfficialSyncServerException {
    return settings.syncServerUrl;
  }
}

String normalizeSyncServerUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const OfficialSyncServerException('官方服务器配置为空');
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) {
    return switch (parsed.scheme) {
      'ws' || 'wss' => _withDefaultWsPath(parsed).toString(),
      'http' => _withDefaultWsPath(parsed.replace(scheme: 'ws')).toString(),
      'https' => _withDefaultWsPath(parsed.replace(scheme: 'wss')).toString(),
      _ => throw OfficialSyncServerException('不支持的服务器协议：${parsed.scheme}'),
    };
  }
  final domainWithPath = trimmed.replaceFirst(RegExp(r'^/+'), '');
  return _withDefaultWsPath(Uri.parse('wss://$domainWithPath')).toString();
}

String _extractServerValue(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    throw const OfficialSyncServerException('官方服务器配置为空');
  }
  late final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return trimmed;
  }
  if (decoded is String) {
    return decoded;
  }
  if (decoded is Map) {
    for (final key in const [
      'server_url',
      'serverUrl',
      'server_domain',
      'serverDomain',
      'domain',
    ]) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
  }
  throw const OfficialSyncServerException('官方服务器配置缺少域名');
}

Uri _withDefaultWsPath(Uri uri) {
  if (uri.host.isEmpty) {
    throw const OfficialSyncServerException('官方服务器域名无效');
  }
  final path = uri.path.isEmpty || uri.path == '/' ? '/ws' : uri.path;
  return uri.replace(path: path);
}

class OfficialSyncServerException implements Exception {
  const OfficialSyncServerException(this.message);

  final String message;

  @override
  String toString() => message;
}
