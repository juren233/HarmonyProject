import 'package:flutter/services.dart';

abstract class SyncSecretStore {
  Future<String?> loadSharedKey();
  Future<void> saveSharedKey(String keyBase64);
  Future<void> deleteSharedKey();
}

class MethodChannelSyncSecretStore implements SyncSecretStore {
  MethodChannelSyncSecretStore({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/ai_secret_store';
  static const String _configId = 'sync.household_key_v1';

  final MethodChannel _channel;
  bool? _availabilityCache;

  Future<bool> isAvailable() async {
    final cached = _availabilityCache;
    if (cached != null) {
      return cached;
    }
    try {
      final available =
          (await _channel.invokeMethod<bool>('isAvailable')) ?? false;
      _availabilityCache = available;
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
  Future<String?> loadSharedKey() async {
    await _ensureAvailable();
    return _channel.invokeMethod<String>('readKey', {'configId': _configId});
  }

  @override
  Future<void> saveSharedKey(String keyBase64) async {
    await _ensureAvailable();
    await _channel.invokeMethod<void>('writeKey', {
      'configId': _configId,
      'value': keyBase64,
    });
  }

  @override
  Future<void> deleteSharedKey() async {
    await _ensureAvailable();
    await _channel.invokeMethod<void>('deleteKey', {'configId': _configId});
  }

  Future<void> _ensureAvailable() async {
    if (!await isAvailable()) {
      throw const SyncSecretStoreException('secure storage unavailable');
    }
  }
}

class InMemorySyncSecretStore implements SyncSecretStore {
  String? _sharedKey;

  @override
  Future<void> deleteSharedKey() async {
    _sharedKey = null;
  }

  @override
  Future<String?> loadSharedKey() async => _sharedKey;

  @override
  Future<void> saveSharedKey(String keyBase64) async {
    _sharedKey = keyBase64;
  }
}

class SyncSecretStoreException implements Exception {
  const SyncSecretStoreException(this.message);

  final String message;

  @override
  String toString() => 'SyncSecretStoreException($message)';
}
