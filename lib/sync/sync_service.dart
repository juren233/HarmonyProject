import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/multi_device_sync_controller.dart';
import 'package:petnote/sync/sync_client.dart';
import 'package:petnote/sync/sync_photo_attachment.dart';
import 'package:petnote/sync/sync_secret_store.dart';
import 'package:petnote/sync/sync_transport.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

typedef SyncTransportFactory = SyncTransport Function(String url);

enum SyncSessionState {
  disconnected,
  connecting,
  handshaking,
  authenticated,
  backingOff,
  blocked,
}

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.connectionState,
    required this.sessionState,
    required this.pendingOutboxCount,
    required this.pendingMutationCount,
    required this.lastPulledServerSeq,
    required this.lastSyncedAt,
    required this.lastPullAt,
    required this.lastError,
    required this.nextRetryAt,
  });

  final SyncConnectionState connectionState;
  final SyncSessionState sessionState;
  final int pendingOutboxCount;
  final int pendingMutationCount;
  final int lastPulledServerSeq;
  final DateTime? lastSyncedAt;
  final DateTime? lastPullAt;
  final Object? lastError;
  final DateTime? nextRetryAt;
}

class SyncService extends ChangeNotifier {
  SyncService({
    required this.settings,
    SyncSecretStore? secretStore,
    OfficialSyncServerResolver? officialServerResolver,
    SyncTransportFactory? transportFactory,
    this.handshakeTimeout = const Duration(seconds: 12),
    this.resolveMergeConflict,
    SyncPhotoAttachmentCodec? photoAttachmentCodec,
  })  : _secretStore = secretStore ?? MethodChannelSyncSecretStore(),
        _officialServerResolver =
            officialServerResolver ?? OfficialSyncServerResolver(),
        _photoAttachmentCodec =
            photoAttachmentCodec ?? const SyncPhotoAttachmentCodec(),
        _transportFactory =
            transportFactory ?? ((url) => SyncClient(url: url)) {
    settings.addListener(_handleSettingsChanged);
    _refreshFailedSyncCount();
  }

  static SyncService? instance;

  final AppSettingsController settings;
  final SyncSecretStore _secretStore;
  final OfficialSyncServerResolver _officialServerResolver;
  final SyncPhotoAttachmentCodec _photoAttachmentCodec;
  final SyncTransportFactory _transportFactory;
  final Duration handshakeTimeout;
  SyncMergeConflictResolver? resolveMergeConflict;

  SyncTransport? _transport;
  MultiDeviceSyncController? _controller;
  _SyncConfig? _activeConfig;
  DeviceRole? _activeRole;
  void Function()? _transportStateListener;
  VoidCallback? _engineFailedCountListener;
  ValueListenable<int>? _engineFailedCount;
  final ValueNotifier<int> _failedSyncCount = ValueNotifier<int>(0);
  bool _initialConnectionCompleted = false;
  bool _handshakeFailed = false;
  String? _lastReportedServedPetId;
  StreamSubscription<SyncMessage>? _helloAckSubscription;
  Timer? _handshakeTimer;
  SyncSessionState _sessionState = SyncSessionState.disconnected;
  PetNoteStore? _activeStore;
  DateTime? _lastPullAt;
  Object? _lastSessionError;

  bool get isActive => _transport != null;
  SyncTransport? get debugTransport => _transport;
  MultiDeviceSyncController? get syncController => _controller;
  MultiDeviceSyncController? get ownerEngine => _controller;
  MultiDeviceSyncController? get petController => _controller;
  @visibleForTesting
  set petController(MultiDeviceSyncController? controller) {
    _controller = controller;
    _activeRole = controller == null ? null : DeviceRole.pet;
  }

  ValueListenable<int>? get failedSyncCount => _failedSyncCount;
  SyncSessionState get sessionState => _sessionState;
  SyncStatusSnapshot get statusSnapshot => SyncStatusSnapshot(
        connectionState:
            _transport?.state.value ?? SyncConnectionState.disconnected,
        sessionState: _sessionState,
        pendingOutboxCount: _controller?.pendingOutboxCount ?? 0,
        pendingMutationCount: _activeStore?.pendingLocalMutations.length ?? 0,
        lastPulledServerSeq: _effectiveLastPulledServerSeq(
          _activeConfig?.householdId ?? settings.householdId,
        ),
        lastSyncedAt: _controller?.lastSyncedAt.value,
        lastPullAt: _lastPullAt,
        lastError: _lastSessionError ?? _controller?.lastError.value,
        nextRetryAt: _controller?.nextOutboxRetryAt,
      );
  Map<String, Object?> buildDiagnosticsSnapshot() {
    final snapshot = statusSnapshot;
    return <String, Object?>{
      'connectionState': snapshot.connectionState.name,
      'sessionState': snapshot.sessionState.name,
      'issueKind': currentIssueKind.name,
      'deviceRole': settings.deviceRole.name,
      'syncServerMode': settings.syncServerMode.name,
      'hasHouseholdId': settings.householdId != null,
      'hasDeviceId': settings.deviceId != null,
      'hasServedPetId': settings.servedPetId != null,
      'hasPendingResetSnapshot': settings.pendingResetSnapshotSyncId != null,
      'pendingOutboxCount': snapshot.pendingOutboxCount,
      'pendingMutationCount': snapshot.pendingMutationCount,
      'failedSyncCount': _failedSyncCount.value,
      'lastPulledServerSeq': snapshot.lastPulledServerSeq,
      'lastSyncedAtMs': snapshot.lastSyncedAt?.millisecondsSinceEpoch,
      'lastPullAtMs': snapshot.lastPullAt?.millisecondsSinceEpoch,
      'nextRetryAtMs': snapshot.nextRetryAt?.millisecondsSinceEpoch,
      'lastErrorType': snapshot.lastError?.runtimeType.toString(),
      'lastErrorKind': _diagnosticErrorKind(snapshot.lastError),
    };
  }

  Future<Map<String, Object?>>
      buildDiagnosticsSnapshotWithPayloadStats() async {
    final diagnostics = Map<String, Object?>.from(buildDiagnosticsSnapshot());
    final store = _activeStore;
    diagnostics['hasActiveStore'] = store != null;
    if (store == null) {
      return diagnostics;
    }

    final state = store.exportDataState();
    final snapshotDataJsonBytes =
        utf8.encode(jsonEncode(state.toJson())).length;
    var petPhotoPathCount = 0;
    var petPhotoUniquePathCount = 0;
    var petPhotoSyncEligibleCount = 0;
    var petPhotoMissingCount = 0;
    var petPhotoEmptyCount = 0;
    var petPhotoTooLargeCount = 0;
    var petPhotoBytes = 0;
    var petPhotoBase64Bytes = 0;
    final seenPhotoPaths = <String>{};

    for (final pet in state.pets) {
      final photoPath = pet.photoPath?.trim();
      if (photoPath == null || photoPath.isEmpty) {
        continue;
      }
      petPhotoPathCount += 1;
      if (!seenPhotoPaths.add(photoPath)) {
        continue;
      }
      petPhotoUniquePathCount += 1;
      final file = File(photoPath);
      try {
        if (!await file.exists()) {
          petPhotoMissingCount += 1;
          continue;
        }
        final length = await file.length();
        if (length <= 0) {
          petPhotoEmptyCount += 1;
          continue;
        }
        if (length > syncPhotoAttachmentMaxBytes) {
          petPhotoTooLargeCount += 1;
          continue;
        }
        petPhotoSyncEligibleCount += 1;
        petPhotoBytes += length;
        petPhotoBase64Bytes += _estimatedBase64Bytes(length);
      } on FileSystemException {
        petPhotoMissingCount += 1;
      }
    }

    final recordPhotoReferenceCount = state.records.fold<int>(
      0,
      (count, record) => count + record.photoPaths.length,
    );
    diagnostics.addAll(<String, Object?>{
      'localPetCount': state.pets.length,
      'localTodoCount': state.todos.length,
      'localReminderCount': state.reminders.length,
      'localRecordCount': state.records.length,
      'snapshotDataJsonBytes': snapshotDataJsonBytes,
      'estimatedSnapshotPayloadBytes':
          snapshotDataJsonBytes + petPhotoBase64Bytes,
      'petPhotoPathCount': petPhotoPathCount,
      'petPhotoUniquePathCount': petPhotoUniquePathCount,
      'petPhotoSyncEligibleCount': petPhotoSyncEligibleCount,
      'petPhotoMissingCount': petPhotoMissingCount,
      'petPhotoEmptyCount': petPhotoEmptyCount,
      'petPhotoTooLargeCount': petPhotoTooLargeCount,
      'petPhotoBytes': petPhotoBytes,
      'petPhotoBase64Bytes': petPhotoBase64Bytes,
      'recordPhotoReferenceCount': recordPhotoReferenceCount,
      'petPhotoMaxBytes': syncPhotoAttachmentMaxBytes,
    });
    return diagnostics;
  }

  String? _diagnosticErrorKind(Object? error) {
    if (error == null) {
      return null;
    }
    if (error is TimeoutException) {
      return 'timeout';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('auth failed')) {
      return 'authFailed';
    }
    if (text.contains('unknown household')) {
      return 'unknownHousehold';
    }
    if (text.contains('secure storage')) {
      return 'secureStorage';
    }
    if (text.contains('outbox') && text.contains('limit')) {
      return 'outboxCapacity';
    }
    return 'unknown';
  }

  int _estimatedBase64Bytes(int rawBytes) {
    if (rawBytes <= 0) {
      return 0;
    }
    return ((rawBytes + 2) ~/ 3) * 4;
  }

  SyncIssueKind get currentIssueKind {
    final baseCount = _controller?.failedSyncCount.value ?? 0;
    if ((_handshakeFailed || _sessionState == SyncSessionState.blocked) &&
        settings.householdId != null) {
      return SyncIssueKind.handshakeFailed;
    }
    if (settings.pendingResetSnapshotSyncId != null) {
      return SyncIssueKind.pendingResetConfirmation;
    }
    if (baseCount > 0) {
      return SyncIssueKind.failedQueue;
    }
    return SyncIssueKind.none;
  }

  Future<void> pushLocalSnapshotToAllDevices({
    required PetNoteStore store,
    SyncDataPolicy dataPolicy = SyncDataPolicy.remoteWins,
  }) async {
    await ensureStarted(store: store, pushStartupSnapshot: false);
    final syncId = dataPolicy == SyncDataPolicy.remoteWins
        ? await _ensurePendingResetSnapshotSyncId()
        : null;
    await _controller?.pushSnapshotNow(
      dataPolicy: dataPolicy,
      force: true,
      syncId: syncId,
    );
    _refreshFailedSyncCount();
  }

  void retrySyncIssues() {
    _restartHandshakeIfConnected();
    _controller?.retryFailedSync();
    if (settings.pendingResetSnapshotSyncId != null && _activeRole != null) {
      unawaited(_pushPendingResetSnapshotIfAny());
    }
    _refreshFailedSyncCount();
  }

  Future<void> ensureStarted({
    required PetNoteStore store,
    bool pushStartupSnapshot = true,
  }) async {
    await _ensureStartedForRole(
      store: store,
      role: settings.deviceRole,
      pushStartupSnapshot: pushStartupSnapshot,
    );
  }

  Future<void> ensureStartedForOwner({
    required PetNoteStore? store,
    bool pushStartupSnapshot = true,
  }) async {
    if (store == null) {
      return;
    }
    await _ensureStartedForRole(
      store: store,
      role: DeviceRole.owner,
      pushStartupSnapshot: pushStartupSnapshot,
    );
  }

  Future<void> ensureStartedForPet({
    required PetNoteStore store,
    bool pushStartupSnapshot = true,
  }) async {
    await _ensureStartedForRole(
      store: store,
      role: DeviceRole.pet,
      pushStartupSnapshot: pushStartupSnapshot,
    );
  }

  Future<void> _ensureStartedForRole({
    required PetNoteStore store,
    required DeviceRole role,
    required bool pushStartupSnapshot,
  }) async {
    if (role == DeviceRole.undecided) {
      return;
    }
    final pendingPolicy = settings.pendingInitialSyncPolicy;
    final config = await _loadConfig();
    if (config == null) {
      if (isActive) {
        await stop();
      }
      return;
    }
    if (isActive) {
      final roleChanged = _activeRole != null && _activeRole != role;
      if (pendingPolicy == null &&
          _activeConfig?.matches(config) == true &&
          identical(_controller?.store, store)) {
        _activeStore = store;
        if (roleChanged) {
          _setActiveRole(role);
          final transport = _transport;
          if (transport != null &&
              transport.state.value == SyncConnectionState.connected) {
            _setSessionState(SyncSessionState.handshaking);
            _sendHello(
              transport: transport,
              config: _activeConfig ?? config,
              role: role,
            );
            _startHandshakeTimer();
          }
        }
        await recoverSync();
        return;
      }
      await stop();
    }
    final transport = _transportFactory(config.url);
    _transport = transport;
    _activeConfig = config;
    _activeStore = store;
    final controller = _createController(
      store: store,
      transport: transport,
    );
    _controller = controller;
    await controller.start(
      pushInitialSnapshot: false,
      requestInitialSnapshot: false,
    );
    _attachEngineFailedCount(_controller?.failedSyncCount);
    _setActiveRole(role);

    _attachHelloAckHandler(transport, config);
    _attachHelloOnConnect(
      transport: transport,
      config: config,
      role: role,
    );
    await _connectTransport(
      transport: transport,
    );

    await _runInitialSyncPolicy(
      pendingPolicy: pendingPolicy,
      pushStartupSnapshot: pushStartupSnapshot,
    );
  }

  Future<void> _runInitialSyncPolicy({
    required SyncDataPolicy? pendingPolicy,
    required bool pushStartupSnapshot,
  }) async {
    if (pendingPolicy == null) {
      final hasPendingReset = settings.pendingResetSnapshotSyncId != null;
      if (!pushStartupSnapshot) {
        await _pushPendingResetSnapshotIfAny();
        _initialConnectionCompleted = true;
        return;
      }
      await _pushPendingResetSnapshotIfAny();
      if (hasPendingReset) {
        _controller?.requestSnapshot();
      } else {
        await _controller?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.merge,
          preserveConflictingIds: true,
        );
        _controller?.requestSnapshot(
          dataPolicy: SyncDataPolicy.merge,
          resolveConflicts: true,
        );
      }
      _initialConnectionCompleted = true;
      return;
    }

    final policy = pendingPolicy;
    await settings.setPendingInitialSyncPolicy(null);

    // 首次连接完成后，根据配对时选择的策略执行同步
    if (policy == SyncDataPolicy.localWins) {
      // 以本机为准：推送本机数据覆盖对方
      await _controller?.pushSnapshotNow(dataPolicy: SyncDataPolicy.remoteWins);
    } else if (policy == SyncDataPolicy.remoteWins) {
      // 以对方为准：请求对方数据并覆盖本机
      _controller?.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);
    } else {
      // 合并：双向传输，对方没有的数据会被添加
      await _controller?.pushSnapshotNow(
        dataPolicy: SyncDataPolicy.merge,
        preserveConflictingIds: true,
      );
      _controller?.requestSnapshot(
        dataPolicy: SyncDataPolicy.merge,
        resolveConflicts: true,
      );
    }
    _initialConnectionCompleted = true;
  }

  MultiDeviceSyncController _createController({
    required PetNoteStore store,
    required SyncTransport transport,
  }) {
    final config = _activeConfig;
    if (config == null) {
      throw StateError('同步配置未加载');
    }
    return MultiDeviceSyncController(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
      onRemoved: _stopAfterRemoval,
      canSend: _canSendBusinessMessages,
      photoAttachmentCodec: _photoAttachmentCodec,
    );
  }

  Future<void> stop() async {
    final shouldNotify = _controller != null || _transport != null;
    final listener = _transportStateListener;
    final transport = _transport;
    final controller = _controller;
    final helloAckSubscription = _helloAckSubscription;
    if (listener != null) {
      transport?.state.removeListener(listener);
      _transportStateListener = null;
    }
    _helloAckSubscription = null;
    _controller = null;
    _transport = null;
    _activeConfig = null;
    _activeRole = null;
    _activeStore = null;
    _initialConnectionCompleted = false;
    _lastReportedServedPetId = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshakeFailed = false;
    _lastSessionError = null;
    _setSessionState(SyncSessionState.disconnected);
    settings.removeListener(_handlePetSettingsChanged);

    await helloAckSubscription?.cancel();
    _helloAckSubscription = null;
    _attachEngineFailedCount(null);
    controller?.dispose();
    await transport?.disconnect();
    if (shouldNotify) {
      _refreshFailedSyncCount();
      notifyListeners();
    }
  }

  Future<void> recoverSync() async {
    final role = _activeRole;
    if (role == null || _transport == null) {
      return;
    }
    if (_transport?.state.value == SyncConnectionState.disconnected) {
      await _connectTransport(transport: _transport!);
      return;
    }
    if (_sessionState == SyncSessionState.authenticated) {
      _retryActiveEngine();
      _requestSnapshotWithCooldown(force: true);
      return;
    }
    _restartHandshakeIfConnected();
  }

  Future<void> _connectTransport({required SyncTransport transport}) async {
    _setSessionState(SyncSessionState.connecting);
    try {
      await transport.connect();
    } on Object catch (error) {
      _handshakeFailed = true;
      _lastSessionError = error;
      _setSessionState(SyncSessionState.backingOff);
      _refreshFailedSyncCount();
      debugPrint('SyncClient connect failed during startup: $error');
    }
  }

  bool _canSendBusinessMessages() {
    return _sessionState == SyncSessionState.authenticated;
  }

  void _setSessionState(SyncSessionState state) {
    if (_sessionState == state) {
      return;
    }
    _sessionState = state;
    notifyListeners();
  }

  void _retryActiveEngine() {
    _controller?.retryFailedSync();
    _refreshFailedSyncCount();
  }

  bool _restartHandshakeIfConnected() {
    final transport = _transport;
    final config = _activeConfig;
    final role = _activeRole;
    if (transport == null ||
        config == null ||
        role == null ||
        _sessionState == SyncSessionState.authenticated ||
        transport.state.value != SyncConnectionState.connected) {
      return false;
    }
    _handshakeFailed = false;
    _lastSessionError = null;
    _setSessionState(SyncSessionState.handshaking);
    _sendHello(
      transport: transport,
      config: config,
      role: role,
    );
    _startHandshakeTimer();
    _queuePostHandshakeRecovery();
    _refreshFailedSyncCount();
    return true;
  }

  void _requestSnapshotWithCooldown({bool force = false}) {
    final now = DateTime.now();
    final lastPullAt = _lastPullAt;
    if (!force &&
        lastPullAt != null &&
        now.difference(lastPullAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastPullAt = now;
    _controller?.requestSnapshot();
  }

  void _stopAfterRemoval() {
    scheduleMicrotask(() {
      unawaited(_clearSecretsAndStopAfterRemoval());
    });
  }

  Future<void> _clearSecretsAndStopAfterRemoval() async {
    try {
      await _secretStore.deleteSharedKey();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'petnote sync',
        context: ErrorDescription('清除解绑后的同步密钥时失败'),
      ));
    } finally {
      await stop();
    }
  }

  Future<_SyncConfig?> _loadConfig() async {
    final url = await resolveConfiguredSyncServerUrl(
      settings: settings,
      officialResolver: _officialServerResolver,
    );
    final householdId = settings.householdId;
    final authToken = settings.householdAuthToken;
    final deviceId = await settings.ensureDeviceId();
    if (url == null || householdId == null) {
      return null;
    }
    String? secureSharedKeyBase64;
    Object? secureSharedKeyError;
    StackTrace? secureSharedKeyStackTrace;
    try {
      secureSharedKeyBase64 = await _secretStore.loadSharedKey();
    } on Object catch (error, stackTrace) {
      secureSharedKeyError = error;
      secureSharedKeyStackTrace = stackTrace;
    }
    final sharedKeyBase64 = secureSharedKeyBase64 ?? settings.sharedKeyBase64;
    if (sharedKeyBase64 == null) {
      if (secureSharedKeyError != null) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: secureSharedKeyError,
          stack: secureSharedKeyStackTrace,
          library: 'petnote sync',
          context: ErrorDescription('读取同步安全密钥失败且没有可用的备份密钥'),
        ));
      }
      return null;
    }
    if (secureSharedKeyError != null) {
      debugPrint('读取同步安全密钥失败，已使用设置中的备份密钥继续同步：'
          '$secureSharedKeyError');
    }
    return _SyncConfig(
      url: url,
      householdId: householdId,
      authToken: authToken,
      deviceId: deviceId,
      sharedKeyBase64: sharedKeyBase64,
    );
  }

  Future<String> _ensurePendingResetSnapshotSyncId() async {
    final existing = settings.pendingResetSnapshotSyncId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final syncId =
        'reset-${DateTime.now().toUtc().microsecondsSinceEpoch}-${await settings.ensureDeviceId()}';
    await settings.setPendingResetSnapshotSyncId(syncId);
    debugPrint('[PetNoteSync] pending reset snapshot registered: $syncId');
    _refreshFailedSyncCount();
    return syncId;
  }

  Future<void> _pushPendingResetSnapshotIfAny() async {
    final syncId = settings.pendingResetSnapshotSyncId;
    if (syncId == null || syncId.isEmpty) {
      return;
    }
    debugPrint('[PetNoteSync] push pending reset snapshot: $syncId');
    await _controller?.pushSnapshotNow(
      dataPolicy: SyncDataPolicy.remoteWins,
      force: true,
      syncId: syncId,
    );
    _refreshFailedSyncCount();
  }

  void _attachEngineFailedCount(ValueListenable<int>? failedCount) {
    final listener = _engineFailedCountListener;
    final current = _engineFailedCount;
    if (listener != null && current != null) {
      current.removeListener(listener);
    }
    _engineFailedCount = failedCount;
    if (failedCount == null) {
      _engineFailedCountListener = null;
      _refreshFailedSyncCount();
      return;
    }
    void nextListener() => _refreshFailedSyncCount();
    _engineFailedCountListener = nextListener;
    failedCount.addListener(nextListener);
    _refreshFailedSyncCount();
  }

  void _refreshFailedSyncCount() {
    if (settings.householdId == null) {
      if (_failedSyncCount.value != 0) {
        _failedSyncCount.value = 0;
      }
      return;
    }
    final nextCount = switch (currentIssueKind) {
      SyncIssueKind.failedQueue => _controller?.failedSyncCount.value ?? 0,
      SyncIssueKind.handshakeFailed ||
      SyncIssueKind.pendingResetConfirmation =>
        1,
      SyncIssueKind.none => 0,
    };
    if (_failedSyncCount.value != nextCount) {
      _failedSyncCount.value = nextCount;
    }
  }

  void _setActiveRole(DeviceRole role) {
    settings.removeListener(_handlePetSettingsChanged);
    _activeRole = role;
    if (role == DeviceRole.pet) {
      _lastReportedServedPetId = settings.servedPetId;
      settings.addListener(_handlePetSettingsChanged);
    } else {
      _lastReportedServedPetId = null;
    }
    notifyListeners();
  }

  void _attachHelloOnConnect({
    required SyncTransport transport,
    required _SyncConfig config,
    required DeviceRole role,
  }) {
    void listener() {
      final state = transport.state.value;
      if (state == SyncConnectionState.connecting) {
        _setSessionState(SyncSessionState.connecting);
        return;
      }
      if (state == SyncConnectionState.disconnected) {
        if (_activeRole != null) {
          _setSessionState(SyncSessionState.backingOff);
        }
        return;
      }
      _setSessionState(SyncSessionState.handshaking);
      final activeRole = _activeRole ?? role;
      _sendHello(
        transport: transport,
        config: _activeConfig ?? config,
        role: activeRole,
      );
      _startHandshakeTimer();
      _queuePostHandshakeRecovery();
    }

    transport.state.addListener(listener);
    _transportStateListener = listener;
  }

  void _queuePostHandshakeRecovery() {
    if (settings.pendingResetSnapshotSyncId != null) {
      unawaited(_pushPendingResetSnapshotIfAny());
    }

    // 只在重连或重新握手时（非首次连接）主动请求快照。
    if (_initialConnectionCompleted) {
      _retryActiveEngine();
      _requestSnapshotWithCooldown();
    }
  }

  void _attachHelloAckHandler(SyncTransport transport, _SyncConfig config) {
    unawaited(_helloAckSubscription?.cancel());
    _helloAckSubscription = transport.messages.listen((message) {
      if (message.type != SyncMessageTypes.helloAck) {
        if (message.type == SyncMessageTypes.pairError) {
          debugPrint(
              '[PetNoteSync] hello failed: ${message.payload['message']}');
          _handshakeFailed = true;
          _lastSessionError =
              message.payload['message'] ?? 'sync handshake failed';
          _handshakeTimer?.cancel();
          _setSessionState(SyncSessionState.blocked);
          _refreshFailedSyncCount();
        }
        return;
      }
      _handshakeTimer?.cancel();
      _handshakeFailed = false;
      _lastSessionError = null;
      _setSessionState(SyncSessionState.authenticated);
      debugPrint(
        '[PetNoteSync] hello acknowledged: '
        'snapshotVersion=${message.payload['snapshotVersion']} '
        'restoredHousehold=${message.payload['restoredHousehold'] == true}',
      );
      _refreshFailedSyncCount();
      final restoredToken = message.payload['authToken'];
      if (config.authToken == null &&
          restoredToken is String &&
          restoredToken.isNotEmpty) {
        unawaited(settings.setHouseholdAuthToken(restoredToken));
        _activeConfig = config.copyWith(authToken: restoredToken);
      }
      if (message.payload['restoredHousehold'] == true) {
        unawaited(Future<void>.sync(() async {
          await _ensurePendingResetSnapshotSyncId();
          await _pushPendingResetSnapshotIfAny();
        }));
      }
      _retryActiveEngine();
    }, onError: (Object error, StackTrace stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'petnote sync',
        context: ErrorDescription('监听同步握手确认时失败'),
      ));
    });
  }

  void _startHandshakeTimer() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(handshakeTimeout, () {
      if (_sessionState != SyncSessionState.handshaking) {
        return;
      }
      _handshakeFailed = true;
      _lastSessionError = TimeoutException('sync handshake timed out');
      _setSessionState(SyncSessionState.blocked);
      _refreshFailedSyncCount();
    });
  }

  void _sendHello({
    required SyncTransport transport,
    required _SyncConfig config,
    required DeviceRole role,
  }) {
    final isOwner = role == DeviceRole.owner;
    debugPrint(
      '[PetNoteSync] send hello: role=${isOwner ? 'owner' : 'pet'} '
      'household=${config.householdId} device=${config.deviceId} '
      'hasAuth=${config.authToken != null}',
    );
    transport.send(
      SyncMessage(SyncMessageTypes.hello, {
        'householdId': config.householdId,
        'deviceId': config.deviceId,
        'role': isOwner ? 'owner' : 'pet',
        if (config.authToken != null) 'authToken': config.authToken,
        'deviceName': settings.deviceName ?? (isOwner ? '主人设备' : '宠物端设备'),
        'lastPulledServerSeq':
            _effectiveLastPulledServerSeq(config.householdId),
        if (!isOwner) 'servedPetId': settings.servedPetId,
      }),
    );
  }

  int _effectiveLastPulledServerSeq(String? householdId) {
    final storeSeq =
        _activeStore?.syncLastPulledServerSeqForHousehold(householdId);
    if (storeSeq == null) {
      return 0;
    }
    final settingsSeq = settings.lastPulledServerSeq;
    return storeSeq < settingsSeq ? storeSeq : settingsSeq;
  }

  void _handlePetSettingsChanged() {
    if (_activeRole != DeviceRole.pet) {
      return;
    }
    final servedPetId = settings.servedPetId;
    if (_lastReportedServedPetId == servedPetId) {
      return;
    }
    _lastReportedServedPetId = servedPetId;
    _controller?.updateServedPetId(servedPetId);
  }

  void _handleSettingsChanged() {
    if (settings.householdId == null) {
      _handshakeFailed = false;
      _lastSessionError = null;
      unawaited(_clearDurableOutboxIfAny());
      if (_sessionState == SyncSessionState.blocked) {
        _setSessionState(SyncSessionState.disconnected);
      }
    }
    _refreshFailedSyncCount();
  }

  Future<void> _clearDurableOutboxIfAny() async {
    final controller = _controller;
    controller?.clearDurableOutbox();
    await controller?.outboxPersistIdle;
    _refreshFailedSyncCount();
  }

  @override
  void dispose() {
    settings.removeListener(_handleSettingsChanged);
    settings.removeListener(_handlePetSettingsChanged);
    _attachEngineFailedCount(null);
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshakeFailed = false;
    _failedSyncCount.dispose();
    super.dispose();
  }
}

enum SyncIssueKind {
  none,
  failedQueue,
  handshakeFailed,
  pendingResetConfirmation,
}

class _SyncConfig {
  const _SyncConfig({
    required this.url,
    required this.householdId,
    this.authToken,
    required this.deviceId,
    required this.sharedKeyBase64,
  });

  final String url;
  final String householdId;
  final String? authToken;
  final String deviceId;
  final String sharedKeyBase64;

  bool matches(_SyncConfig other) {
    return url == other.url &&
        householdId == other.householdId &&
        authToken == other.authToken &&
        deviceId == other.deviceId &&
        sharedKeyBase64 == other.sharedKeyBase64;
  }

  _SyncConfig copyWith({String? authToken}) {
    return _SyncConfig(
      url: url,
      householdId: householdId,
      authToken: authToken ?? this.authToken,
      deviceId: deviceId,
      sharedKeyBase64: sharedKeyBase64,
    );
  }
}
