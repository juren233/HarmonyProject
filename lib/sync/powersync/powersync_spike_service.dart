// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/powersync/powersync_backend_connector.dart';
import 'package:petnote/sync/powersync/powersync_spike_adapter.dart';
import 'package:powersync/powersync.dart';

typedef PowerSyncSpikeBridgeOpener = Future<PowerSyncSpikeDataBridge> Function({
  required PetNotePowerSyncConnector connector,
});

class PowerSyncSpikeService extends ChangeNotifier {
  PowerSyncSpikeService({
    required this.settings,
    OfficialSyncServerResolver? officialServerResolver,
    PowerSyncSpikeBridgeOpener? bridgeOpener,
    this.mirrorThrottle = const Duration(milliseconds: 500),
  })  : _officialServerResolver =
            officialServerResolver ?? OfficialSyncServerResolver(),
        _bridgeOpener = bridgeOpener ??
            (({required connector}) =>
                PetNotePowerSyncSpikeAdapter.open(connector: connector)) {
    settings.addListener(_refreshFailedSyncCount);
    _refreshFailedSyncCount();
  }

  final AppSettingsController settings;
  final OfficialSyncServerResolver _officialServerResolver;
  final PowerSyncSpikeBridgeOpener _bridgeOpener;
  final Duration mirrorThrottle;

  final ValueNotifier<Object?> lastError = ValueNotifier<Object?>(null);
  final ValueNotifier<int> failedSyncCount = ValueNotifier<int>(0);
  final ValueNotifier<SyncStatus> connectionStatus =
      ValueNotifier<SyncStatus>(const SyncStatus());

  PowerSyncSpikeDataBridge? _bridge;
  PetNotePowerSyncConnector? _connector;
  PetNoteStore? _store;
  _PowerSyncSpikeConfig? _activeConfig;
  StreamSubscription<PetNoteDataState>? _remoteSubscription;
  VoidCallback? _statusListener;
  Timer? _mirrorTimer;
  bool _applyingRemoteState = false;
  String? _lastStoreJson;
  String? _lastMirroredJson;

  bool get isActive => _bridge != null;

  Future<void> ensureStarted({required PetNoteStore store}) async {
    final config = await _loadConfig();
    if (config == null) {
      await stop();
      return;
    }
    if (isActive &&
        identical(_store, store) &&
        _activeConfig?.matches(config) == true) {
      return;
    }
    await stop();

    final connector = PetNotePowerSyncConnector(
      syncServerUrl: config.url,
      householdId: config.householdId,
      authToken: config.authToken,
      deviceId: config.deviceId,
      role: config.role,
    );
    try {
      final bridge = await _bridgeOpener(connector: connector);
      _connector = connector;
      _bridge = bridge;
      _store = store;
      _activeConfig = config;
      _attachBridgeStatus(bridge);

      final remoteState = await bridge.readDataState();
      if (_hasData(remoteState)) {
        await _applyRemoteState(remoteState);
      } else if (_shouldSeedRemoteFromLocal(config, store.exportDataState())) {
        await pushStoreNow();
      }

      store.addListener(_handleStoreChanged);
      _remoteSubscription = bridge.watchDataState().listen(
        (state) {
          unawaited(_applyRemoteState(state));
        },
        onError: (Object error, StackTrace stackTrace) {
          _recordError(error, stackTrace);
        },
      );
      _refreshFailedSyncCount();
      notifyListeners();
    } on Object catch (error, stackTrace) {
      connector.dispose();
      _recordError(error, stackTrace);
      await stop();
    }
  }

  Future<void> pushStoreNow() async {
    final store = _store;
    final bridge = _bridge;
    final config = _activeConfig;
    if (store == null || bridge == null || config == null) {
      return;
    }
    final state = store.exportDataState();
    if (!_shouldMirrorLocalState(config, state)) {
      return;
    }
    final stateJson = _stateJson(state);
    if (stateJson == _lastMirroredJson) {
      return;
    }
    try {
      await bridge.mirrorLocalDataState(
        state: state,
        householdId: config.householdId,
        ownerDeviceId: config.deviceId,
        updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        role: config.role,
      );
      _lastStoreJson = stateJson;
      _lastMirroredJson = stateJson;
      lastError.value = null;
      _refreshFailedSyncCount();
    } on Object catch (error, stackTrace) {
      _recordError(error, stackTrace);
    }
  }

  Future<void> stop() async {
    _mirrorTimer?.cancel();
    _mirrorTimer = null;
    final store = _store;
    if (store != null) {
      store.removeListener(_handleStoreChanged);
    }
    _store = null;
    await _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _detachBridgeStatus();
    await _bridge?.close();
    _bridge = null;
    _connector?.dispose();
    _connector = null;
    _activeConfig = null;
    _applyingRemoteState = false;
    _lastStoreJson = null;
    _lastMirroredJson = null;
    _refreshFailedSyncCount();
    notifyListeners();
  }

  void _attachBridgeStatus(PowerSyncSpikeDataBridge bridge) {
    _detachBridgeStatus();
    void listener() {
      connectionStatus.value = bridge.status.value;
      final error = bridge.status.value.anyError;
      if (error != null) {
        lastError.value = error;
      } else if (lastError.value == null) {
        lastError.value = null;
      }
      _refreshFailedSyncCount();
    }

    _statusListener = listener;
    bridge.status.addListener(listener);
    listener();
  }

  void _detachBridgeStatus() {
    final listener = _statusListener;
    final bridge = _bridge;
    if (listener != null && bridge != null) {
      bridge.status.removeListener(listener);
    }
    _statusListener = null;
    connectionStatus.value = const SyncStatus();
  }

  Future<_PowerSyncSpikeConfig?> _loadConfig() async {
    if (settings.deviceRole == DeviceRole.undecided) {
      return null;
    }
    final url = await resolveConfiguredSyncServerUrl(
      settings: settings,
      officialResolver: _officialServerResolver,
    );
    final householdId = settings.householdId;
    final authToken = settings.householdAuthToken;
    final deviceId = await settings.ensureDeviceId();
    if (url == null ||
        householdId == null ||
        householdId.isEmpty ||
        authToken == null ||
        authToken.isEmpty) {
      return null;
    }
    return _PowerSyncSpikeConfig(
      url: url,
      householdId: householdId,
      authToken: authToken,
      deviceId: deviceId,
      role: settings.deviceRole == DeviceRole.pet ? 'pet' : 'owner',
    );
  }

  void _handleStoreChanged() {
    if (_applyingRemoteState) {
      return;
    }
    _mirrorTimer?.cancel();
    _mirrorTimer = Timer(mirrorThrottle, () {
      unawaited(pushStoreNow());
    });
  }

  Future<void> _applyRemoteState(PetNoteDataState state) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final stateJson = _stateJson(state);
    if (stateJson == _lastStoreJson) {
      return;
    }
    _applyingRemoteState = true;
    try {
      await store.replaceAllDataFromRemote(state);
      _lastStoreJson = stateJson;
      _lastMirroredJson = stateJson;
      lastError.value = null;
      _refreshFailedSyncCount();
    } on Object catch (error, stackTrace) {
      _recordError(error, stackTrace);
    } finally {
      _applyingRemoteState = false;
    }
  }

  void _recordError(Object error, StackTrace stackTrace) {
    lastError.value = error;
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'petnote powersync spike',
      context: ErrorDescription('运行 PowerSync spike 同步时失败'),
    ));
    _refreshFailedSyncCount();
  }

  void _refreshFailedSyncCount() {
    final statusError = connectionStatus.value.anyError;
    final nextCount = lastError.value == null && statusError == null ? 0 : 1;
    if (failedSyncCount.value != nextCount) {
      failedSyncCount.value = nextCount;
    }
  }

  @override
  void dispose() {
    settings.removeListener(_refreshFailedSyncCount);
    lastError.dispose();
    failedSyncCount.dispose();
    connectionStatus.dispose();
    super.dispose();
  }
}

bool _hasData(PetNoteDataState state) {
  return state.pets.isNotEmpty ||
      state.todos.isNotEmpty ||
      state.reminders.isNotEmpty ||
      state.records.isNotEmpty;
}

bool _shouldSeedRemoteFromLocal(
  _PowerSyncSpikeConfig config,
  PetNoteDataState state,
) {
  return config.role == 'owner' && _hasData(state);
}

bool _shouldMirrorLocalState(
  _PowerSyncSpikeConfig config,
  PetNoteDataState state,
) {
  if (_hasData(state)) {
    return true;
  }
  return config.role == 'owner';
}

String _stateJson(PetNoteDataState state) => jsonEncode(state.toJson());

class _PowerSyncSpikeConfig {
  const _PowerSyncSpikeConfig({
    required this.url,
    required this.householdId,
    required this.authToken,
    required this.deviceId,
    required this.role,
  });

  final String url;
  final String householdId;
  final String authToken;
  final String deviceId;
  final String role;

  bool matches(_PowerSyncSpikeConfig other) {
    return url == other.url &&
        householdId == other.householdId &&
        authToken == other.authToken &&
        deviceId == other.deviceId &&
        role == other.role;
  }
}
