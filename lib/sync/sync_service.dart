import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:petnote/state/app_settings_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/official_sync_server_resolver.dart';
import 'package:petnote/sync/owner_sync_engine.dart';
import 'package:petnote/sync/pet_replica_controller.dart';
import 'package:petnote/sync/sync_client.dart';
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
  })  : _secretStore = secretStore ?? MethodChannelSyncSecretStore(),
        _officialServerResolver =
            officialServerResolver ?? OfficialSyncServerResolver(),
        _transportFactory =
            transportFactory ?? ((url) => SyncClient(url: url)) {
    settings.addListener(_handleSettingsChanged);
    _refreshFailedSyncCount();
  }

  static SyncService? instance;

  final AppSettingsController settings;
  final SyncSecretStore _secretStore;
  final OfficialSyncServerResolver _officialServerResolver;
  final SyncTransportFactory _transportFactory;
  final Duration handshakeTimeout;
  SyncMergeConflictResolver? resolveMergeConflict;

  SyncTransport? _transport;
  OwnerSyncEngine? ownerEngine;
  PetReplicaController? petController;
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
  ValueListenable<int>? get failedSyncCount => _failedSyncCount;
  SyncSessionState get sessionState => _sessionState;
  SyncStatusSnapshot get statusSnapshot => SyncStatusSnapshot(
        connectionState:
            _transport?.state.value ?? SyncConnectionState.disconnected,
        sessionState: _sessionState,
        pendingOutboxCount: ownerEngine?.pendingOutboxCount ??
            petController?.pendingOutboxCount ??
            0,
        pendingMutationCount: _activeStore?.pendingLocalMutations.length ?? 0,
        lastPulledServerSeq: settings.lastPulledServerSeq,
        lastSyncedAt: ownerEngine?.lastSyncedAt.value ??
            petController?.lastSyncedAt.value,
        lastPullAt: _lastPullAt,
        lastError: _lastSessionError ??
            ownerEngine?.lastError.value ??
            petController?.lastError.value,
        nextRetryAt:
            ownerEngine?.nextOutboxRetryAt ?? petController?.nextOutboxRetryAt,
      );
  SyncIssueKind get currentIssueKind {
    final baseCount = ownerEngine?.failedSyncCount.value ??
        petController?.failedSyncCount.value ??
        0;
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
    switch (_activeRole) {
      case DeviceRole.owner:
        final syncId = dataPolicy == SyncDataPolicy.remoteWins
            ? await _ensurePendingResetSnapshotSyncId()
            : null;
        await ownerEngine?.pushSnapshotNow(
          dataPolicy: dataPolicy,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.pet:
        final syncId = dataPolicy == SyncDataPolicy.remoteWins
            ? await _ensurePendingResetSnapshotSyncId()
            : null;
        await petController?.pushSnapshotNow(
          dataPolicy: dataPolicy,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.undecided:
      case null:
        break;
    }
    _refreshFailedSyncCount();
  }

  void retrySyncIssues() {
    ownerEngine?.retryFailedSync();
    petController?.retryFailedSync();
    final role = _activeRole;
    if (settings.pendingResetSnapshotSyncId != null && role != null) {
      unawaited(_pushPendingResetSnapshotIfAny(role));
    }
    _refreshFailedSyncCount();
  }

  Future<void> ensureStarted({
    required PetNoteStore store,
    bool pushStartupSnapshot = true,
  }) async {
    switch (settings.deviceRole) {
      case DeviceRole.owner:
        await ensureStartedForOwner(
          store: store,
          pushStartupSnapshot: pushStartupSnapshot,
        );
      case DeviceRole.pet:
        await ensureStartedForPet(
          store: store,
          pushStartupSnapshot: pushStartupSnapshot,
        );
      case DeviceRole.undecided:
        return;
    }
  }

  Future<void> ensureStartedForOwner({
    required PetNoteStore? store,
    bool pushStartupSnapshot = true,
  }) async {
    if (store == null) {
      return;
    }
    final pendingPolicy = settings.pendingInitialSyncPolicy;
    if (_activeRole == DeviceRole.pet) {
      await stop();
    }
    final config = await _loadConfig();
    if (config == null) {
      if (isActive) {
        await stop();
      }
      return;
    }
    if (isActive) {
      if (pendingPolicy == null && _activeConfig?.matches(config) == true) {
        _activeStore = store;
        await recoverSync();
        return;
      }
      await stop();
    }
    final transport = _transportFactory(config.url);
    _transport = transport;
    _activeConfig = config;
    _activeStore = store;
    final engine = OwnerSyncEngine(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
      onRemoved: _stopAfterRemoval,
      canSend: _canSendBusinessMessages,
    );
    ownerEngine = engine;
    await engine.start(
      pushInitialSnapshot: false,
      requestInitialSnapshot: false,
    );
    _attachEngineFailedCount(ownerEngine?.failedSyncCount);
    _activeRole = DeviceRole.owner;
    notifyListeners();

    _attachHelloAckHandler(transport, config);
    _attachHelloOnConnect(
      transport: transport,
      config: config,
      role: DeviceRole.owner,
    );
    await _connectTransport(
      transport: transport,
    );

    if (pendingPolicy == null) {
      final hasPendingReset = settings.pendingResetSnapshotSyncId != null;
      if (!pushStartupSnapshot) {
        await _pushPendingResetSnapshotIfAny(DeviceRole.owner);
        _initialConnectionCompleted = true;
        return;
      }
      await _pushPendingResetSnapshotIfAny(DeviceRole.owner);
      if (hasPendingReset) {
        ownerEngine?.requestSnapshot();
      } else {
        await ownerEngine?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.merge,
          preserveConflictingIds: true,
        );
        ownerEngine?.requestSnapshot(
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
    if (policy == SyncDataPolicy.remoteWins) {
      // 以对方为准：请求对方数据并覆盖本机
      ownerEngine?.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);
    } else if (policy == SyncDataPolicy.localWins) {
      // 以本机为准：推送本机数据覆盖对方
      await ownerEngine?.pushSnapshotNow(
        dataPolicy: SyncDataPolicy.remoteWins,
      );
    } else {
      // 合并：双向传输，对方没有的数据会被添加
      await ownerEngine?.pushSnapshotNow(
        dataPolicy: SyncDataPolicy.merge,
        preserveConflictingIds: true,
      );
      ownerEngine?.requestSnapshot(resolveConflicts: true);
    }
    _initialConnectionCompleted = true;
  }

  Future<void> ensureStartedForPet({
    required PetNoteStore store,
    bool pushStartupSnapshot = true,
  }) async {
    final pendingPolicy = settings.pendingInitialSyncPolicy;
    if (_activeRole == DeviceRole.owner) {
      await stop();
    }
    final config = await _loadConfig();
    if (config == null) {
      if (isActive) {
        await stop();
      }
      return;
    }
    if (isActive) {
      if (pendingPolicy == null && _activeConfig?.matches(config) == true) {
        _activeStore = store;
        await recoverSync();
        return;
      }
      await stop();
    }
    final transport = _transportFactory(config.url);
    _transport = transport;
    _activeConfig = config;
    _activeStore = store;
    final controller = PetReplicaController(
      store: store,
      transport: transport,
      crypto: SyncCrypto.fromKeyBase64(config.sharedKeyBase64),
      resolveMergeConflict: resolveMergeConflict,
      settings: settings,
      onRemoved: _stopAfterRemoval,
      canSend: _canSendBusinessMessages,
    );
    petController = controller;
    await controller.start(
      pushInitialSnapshot: false,
      requestInitialSnapshot: false,
    );
    _attachEngineFailedCount(petController?.failedSyncCount);
    _activeRole = DeviceRole.pet;
    notifyListeners();

    _attachHelloAckHandler(transport, config);
    _attachHelloOnConnect(
      transport: transport,
      config: config,
      role: DeviceRole.pet,
    );
    _lastReportedServedPetId = settings.servedPetId;
    settings.addListener(_handlePetSettingsChanged);
    await _connectTransport(
      transport: transport,
    );

    if (pendingPolicy == null) {
      final hasPendingReset = settings.pendingResetSnapshotSyncId != null;
      if (!pushStartupSnapshot) {
        await _pushPendingResetSnapshotIfAny(DeviceRole.pet);
        _initialConnectionCompleted = true;
        return;
      }
      await _pushPendingResetSnapshotIfAny(DeviceRole.pet);
      if (hasPendingReset) {
        petController?.requestSnapshot();
      } else {
        await petController?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.merge,
          preserveConflictingIds: true,
        );
        petController?.requestSnapshot(
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
      await petController?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins);
    } else if (policy == SyncDataPolicy.remoteWins) {
      // 以对方为准：请求对方数据并覆盖本机
      petController?.requestSnapshot(dataPolicy: SyncDataPolicy.remoteWins);
    } else {
      // 合并：双向传输，对方没有的数据会被添加
      petController?.requestSnapshot(
        dataPolicy: SyncDataPolicy.merge,
        resolveConflicts: true,
      );
      await petController?.pushSnapshotNow(
        dataPolicy: SyncDataPolicy.merge,
        preserveConflictingIds: true,
      );
    }
    _initialConnectionCompleted = true;
  }

  Future<void> stop() async {
    final shouldNotify =
        ownerEngine != null || petController != null || _transport != null;
    final listener = _transportStateListener;
    if (listener != null) {
      _transport?.state.removeListener(listener);
      _transportStateListener = null;
    }
    await _helloAckSubscription?.cancel();
    _helloAckSubscription = null;
    _attachEngineFailedCount(null);
    ownerEngine?.dispose();
    petController?.dispose();
    ownerEngine = null;
    petController = null;
    await _transport?.disconnect();
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
      _requestSnapshotWithCooldown(role, force: true);
    }
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
    ownerEngine?.retryFailedSync();
    petController?.retryFailedSync();
    _refreshFailedSyncCount();
  }

  void _requestSnapshotWithCooldown(DeviceRole role, {bool force = false}) {
    final now = DateTime.now();
    final lastPullAt = _lastPullAt;
    if (!force &&
        lastPullAt != null &&
        now.difference(lastPullAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastPullAt = now;
    switch (role) {
      case DeviceRole.owner:
        ownerEngine?.requestSnapshot();
      case DeviceRole.pet:
        petController?.requestSnapshot();
      case DeviceRole.undecided:
        break;
    }
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

  Future<void> _pushPendingResetSnapshotIfAny(DeviceRole role) async {
    final syncId = settings.pendingResetSnapshotSyncId;
    if (syncId == null || syncId.isEmpty) {
      return;
    }
    switch (role) {
      case DeviceRole.owner:
        debugPrint(
            '[PetNoteSync] push pending reset snapshot as owner: $syncId');
        await ownerEngine?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.pet:
        debugPrint('[PetNoteSync] push pending reset snapshot as pet: $syncId');
        await petController?.pushSnapshotNow(
          dataPolicy: SyncDataPolicy.remoteWins,
          force: true,
          syncId: syncId,
        );
      case DeviceRole.undecided:
        break;
    }
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
      SyncIssueKind.failedQueue => ownerEngine?.failedSyncCount.value ??
          petController?.failedSyncCount.value ??
          0,
      SyncIssueKind.handshakeFailed ||
      SyncIssueKind.pendingResetConfirmation =>
        1,
      SyncIssueKind.none => 0,
    };
    if (_failedSyncCount.value != nextCount) {
      _failedSyncCount.value = nextCount;
    }
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
      _sendHello(
        transport: transport,
        config: _activeConfig ?? config,
        role: role,
      );
      _startHandshakeTimer();
      if (settings.pendingResetSnapshotSyncId != null) {
        unawaited(_pushPendingResetSnapshotIfAny(role));
      }

      // 只在重连时（非首次连接）主动请求快照
      if (_initialConnectionCompleted) {
        _retryActiveEngine();
        _requestSnapshotWithCooldown(role);
      }
    }

    transport.state.addListener(listener);
    _transportStateListener = listener;
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
        switch (_activeRole) {
          case DeviceRole.owner:
            unawaited(Future<void>.sync(() async {
              await _ensurePendingResetSnapshotSyncId();
              await _pushPendingResetSnapshotIfAny(DeviceRole.owner);
            }));
          case DeviceRole.pet:
            unawaited(Future<void>.sync(() async {
              await _ensurePendingResetSnapshotSyncId();
              await _pushPendingResetSnapshotIfAny(DeviceRole.pet);
            }));
          case DeviceRole.undecided:
          case null:
            break;
        }
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
        'lastPulledServerSeq': settings.lastPulledServerSeq,
        if (!isOwner) 'servedPetId': settings.servedPetId,
      }),
    );
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
    petController?.updateServedPetId(servedPetId);
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
    final owner = ownerEngine;
    final pet = petController;
    owner?.clearDurableOutbox();
    pet?.clearDurableOutbox();
    await owner?.outboxPersistIdle;
    await pet?.outboxPersistIdle;
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
