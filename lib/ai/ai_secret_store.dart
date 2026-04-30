import 'package:flutter/services.dart';

abstract class AiSecretStore {
  Future<bool> isAvailable();

  Future<String?> readKey(String configId);

  Future<void> writeKey(String configId, String value);

  Future<void> deleteKey(String configId);

  Future<Map<String, bool>> hasKeys(Iterable<String> configIds) async {
    final result = <String, bool>{};
    for (final configId in configIds.toSet()) {
      final value = await readKey(configId);
      result[configId] = value != null && value.isNotEmpty;
    }
    return result;
  }
}

class MethodChannelAiSecretStore implements AiSecretStore {
  MethodChannelAiSecretStore({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/ai_secret_store';

  final MethodChannel _channel;
  bool? _availabilityCache;

  @override
  Future<bool> isAvailable() async {
    final cached = _availabilityCache;
    if (cached != null) {
      return cached;
    }
    try {
      final available =
          (await _channel.invokeMethod<bool>('isAvailable')) ?? false;
      _availabilityCache = available;
      if (!available) {}
      return available;
    } on PlatformException {
      _availabilityCache = false;
      return false;
    } on MissingPluginException {
      _availabilityCache = false;
      return false;
    }
  }

  @override
  Future<String?> readKey(String configId) async {
    await _ensureAvailable();
    return _readKeyUnchecked(configId);
  }

  Future<String?> _readKeyUnchecked(String configId) async {
    try {
      final value = await _channel
          .invokeMethod<String>('readKey', {'configId': configId});
      return value;
    } on PlatformException {
      rethrow;
    }
  }

  @override
  Future<Map<String, bool>> hasKeys(Iterable<String> configIds) async {
    final ids = configIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return <String, bool>{};
    }
    await _ensureAvailable();
    try {
      final rawResult = await _channel.invokeMethod<Map<Object?, Object?>>(
        'hasKeys',
        <String, Object?>{'configIds': ids},
      );
      return <String, bool>{
        for (final id in ids) id: rawResult?[id] == true,
      };
    } on MissingPluginException {
      return _hasKeysByReading(ids);
    } on PlatformException catch (error) {
      if (error.code == 'MissingPluginException' ||
          error.code == 'notImplemented') {
        return _hasKeysByReading(ids);
      }
      rethrow;
    }
  }

  Future<Map<String, bool>> _hasKeysByReading(List<String> configIds) async {
    final result = <String, bool>{};
    for (final configId in configIds) {
      final value = await _readKeyUnchecked(configId);
      result[configId] = value != null && value.isNotEmpty;
    }
    return result;
  }

  @override
  Future<void> writeKey(String configId, String value) async {
    await _ensureAvailable();
    try {
      await _channel.invokeMethod<void>('writeKey', {
        'configId': configId,
        'value': value,
      });
    } on PlatformException {
      rethrow;
    }
  }

  @override
  Future<void> deleteKey(String configId) async {
    await _ensureAvailable();
    try {
      await _channel.invokeMethod<void>('deleteKey', {'configId': configId});
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> _ensureAvailable() async {
    if (!await isAvailable()) {
      throw const AiSecretStoreException('secure storage unavailable');
    }
  }
}

class InMemoryAiSecretStore implements AiSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> deleteKey(String configId) async {
    _values.remove(configId);
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> readKey(String configId) async => _values[configId];

  @override
  Future<void> writeKey(String configId, String value) async {
    _values[configId] = value;
  }

  @override
  Future<Map<String, bool>> hasKeys(Iterable<String> configIds) async {
    return <String, bool>{
      for (final configId in configIds.toSet())
        configId: _values[configId]?.isNotEmpty == true,
    };
  }
}

class AiSecretStoreException implements Exception {
  const AiSecretStoreException(this.message);

  final String message;

  @override
  String toString() => 'AiSecretStoreException($message)';
}
