import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/app/pet_photo_widgets.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/app/system_ui_policy.dart';
import 'package:petnote/rtc/method_channel_rtc_adapter.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_token_client.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/rtc/rtc_video_view.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

const Size _previewSize = Size(104, 154);
const double _previewMargin = 18;
const double _previewControlClearance = 110;
const Duration _deviceDirectoryWaitTimeout = Duration(seconds: 2);

const SystemUiOverlayStyle _remoteVideoSystemUiOverlayStyle =
    SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarDividerColor: Color(0x00000000),
  systemNavigationBarIconBrightness: Brightness.light,
);

enum _VideoFeed { local, remote }

class RemoteVideoCallPage extends StatefulWidget {
  const RemoteVideoCallPage({
    super.key,
    required this.mode,
    required this.pet,
    this.devicesOverride,
    this.signalingController,
    this.tokenClient,
    this.rtcAdapter,
    this.userId,
    this.callId,
    this.targetDeviceId,
    this.sendInviteOnJoin = true,
  });

  final RemoteVideoMode mode;
  final Pet pet;
  final List<SyncedDeviceInfo>? devicesOverride;
  final RtcSignalingController? signalingController;
  final RtcTokenClient? tokenClient;
  final RtcAdapter? rtcAdapter;
  final String? userId;
  final String? callId;
  final String? targetDeviceId;
  final bool sendInviteOnJoin;

  @override
  State<RemoteVideoCallPage> createState() => _RemoteVideoCallPageState();
}

class _RemoteVideoCallPageState extends State<RemoteVideoCallPage>
    with WidgetsBindingObserver {
  bool _initializing = false;
  bool _rtcJoined = false;
  bool _disposed = false;
  bool _micEnabled = true;
  bool _speakerEnabled = true;
  bool _cameraEnabled = true;
  bool _remoteCameraEnabled = true;
  bool _localVideoOnMain = false;
  bool _isDraggingPreview = false;
  bool _retryAfterFailureRequested = false;
  String? _statusOverride;
  Offset? _previewOffset;
  RtcAdapter? _ownedAdapter;
  RtcTokenClient? _ownedTokenClient;
  Uri? _ownedTokenClientBaseUri;
  RtcSignalingController? _ownedSignalingController;
  StreamSubscription<RtcCallSignal>? _signalSubscription;
  Timer? _callTimer;
  DateTime? _connectedAt;
  Duration _callElapsed = Duration.zero;
  late final String _resolvedCallId;

  String get _callId => _resolvedCallId;

  String? get _targetDeviceId {
    if (widget.targetDeviceId != null &&
        widget.targetDeviceId!.trim().isNotEmpty) {
      return widget.targetDeviceId;
    }
    return selectedRemoteVideoDevice(
      pet: widget.pet,
      devices: widget.devicesOverride ??
          SyncService.instance?.syncController?.devices.value ??
          const [],
    )?.deviceId;
  }

  RtcAdapter? get _rtcAdapter => widget.rtcAdapter ?? _ownedAdapter;

  RtcSignalingController? get _signalingController =>
      widget.signalingController ?? _ownedSignalingController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enterImmersiveSystemUi());
    _resolvedCallId = widget.callId ?? _newRtcCallId(widget.mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_startRtc());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    unawaited(configureStartupSystemUi());
    unawaited(_signalSubscription?.cancel());
    unawaited(_teardownRtc());
    _ownedTokenClient?.dispose();
    unawaited(_ownedSignalingController?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _rtcJoined) {
      _sendMediaState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectedDevice = selectedRemoteVideoDevice(
      pet: widget.pet,
      devices: widget.devicesOverride ??
          SyncService.instance?.syncController?.devices.value ??
          const [],
    );
    final statusLabel = connectedDevice == null
        ? '未配对宠物端'
        : '${connectedDevice.name} ${connectedDevice.online ? '在线' : '离线'}';
    final title = widget.mode == RemoteVideoMode.call ? '视频通话' : '先看看它';
    final callStateLabel =
        _rtcJoined ? _statusOverride : _statusOverride ?? '发起中';
    final surfaceStatus = _statusOverride ?? statusLabel;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _remoteVideoSystemUiOverlayStyle,
      child: Scaffold(
        backgroundColor: const Color(0xFF101114),
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final mediaPadding = MediaQuery.viewPaddingOf(context);
            final previewBounds = _previewBounds(
              Size(constraints.maxWidth, constraints.maxHeight),
              mediaPadding,
            );
            final previewOffset = _resolvedPreviewOffset(previewBounds);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _RemoteVideoSurface(
                    title: title,
                    statusLabel: surfaceStatus,
                    petName: widget.pet.name,
                    remoteUserId: _targetDeviceId,
                    isConnected: _rtcJoined,
                    feed: _localVideoOnMain
                        ? _VideoFeed.local
                        : _VideoFeed.remote,
                    localCameraEnabled: _cameraEnabled,
                    remoteCameraEnabled: _remoteCameraEnabled,
                  ),
                ),
                Positioned(
                  top: mediaPadding.top + 18,
                  left: 18,
                  right: 18,
                  child: _CallHeader(
                    pet: widget.pet,
                    title: title,
                    statusLabel: callStateLabel,
                    elapsedLabel: _connectedAt == null
                        ? null
                        : _formatElapsed(_callElapsed),
                  ),
                ),
                AnimatedPositioned(
                  key: const ValueKey('remote_video_preview_positioned'),
                  duration: _isDraggingPreview
                      ? Duration.zero
                      : const Duration(milliseconds: 520),
                  curve: Curves.elasticOut,
                  left: previewOffset.dx,
                  top: previewOffset.dy,
                  child: _FloatingVideoPreview(
                    feed: _localVideoOnMain
                        ? _VideoFeed.remote
                        : _VideoFeed.local,
                    remoteUserId: _targetDeviceId,
                    isConnected: _rtcJoined,
                    localCameraEnabled: _cameraEnabled,
                    remoteCameraEnabled: _remoteCameraEnabled,
                    onTap: _swapMainVideo,
                    onPanUpdate: (details) =>
                        _dragPreview(details.delta, previewOffset),
                    onPanEnd: () => _settlePreview(previewBounds),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: mediaPadding.bottom + 22,
                  child: _CallControls(
                    micEnabled: _micEnabled,
                    speakerEnabled: _speakerEnabled,
                    cameraEnabled: _cameraEnabled,
                    onToggleMic: _toggleMic,
                    onToggleSpeaker: _toggleSpeaker,
                    onToggleCamera: _toggleCamera,
                    onSwitchCamera: _switchCamera,
                    onHangup: () => unawaited(_hangup()),
                    isBusy: _initializing,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _enterImmersiveSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(_remoteVideoSystemUiOverlayStyle);
  }

  Rect _previewBounds(Size size, EdgeInsets padding) {
    final left = padding.left + _previewMargin;
    final top = padding.top + _previewMargin;
    final right =
        size.width - padding.right - _previewMargin - _previewSize.width;
    final bottom = size.height -
        padding.bottom -
        _previewControlClearance -
        _previewSize.height;
    return Rect.fromLTRB(
      left,
      top,
      right < left ? left : right,
      bottom < top ? top : bottom,
    );
  }

  Offset _resolvedPreviewOffset(Rect bounds) {
    final current = _previewOffset ??
        Offset(
          bounds.right,
          bounds.bottom,
        );
    if (_isDraggingPreview) {
      return current;
    }
    return _clampPreviewOffset(current, bounds);
  }

  Offset _clampPreviewOffset(Offset offset, Rect bounds) {
    return Offset(
      offset.dx.clamp(bounds.left, bounds.right).toDouble(),
      offset.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
  }

  double _rubberBandAxis(double value, double min, double max) {
    if (value < min) {
      return min - _rubberBandDistance(min - value);
    }
    if (value > max) {
      return max + _rubberBandDistance(value - max);
    }
    return value;
  }

  double _rubberBandDistance(double overflow) {
    return 72 * (1 - 1 / (overflow / 72 + 1));
  }

  Offset _rubberBandPreviewOffset(Offset offset, Rect bounds) {
    return Offset(
      _rubberBandAxis(offset.dx, bounds.left, bounds.right),
      _rubberBandAxis(offset.dy, bounds.top, bounds.bottom),
    );
  }

  void _dragPreview(Offset delta, Offset currentOffset) {
    final bounds = _previewBounds(
      MediaQuery.sizeOf(context),
      MediaQuery.viewPaddingOf(context),
    );
    setState(() {
      _isDraggingPreview = true;
      _previewOffset = _rubberBandPreviewOffset(
        (_previewOffset ?? currentOffset) + delta,
        bounds,
      );
    });
  }

  void _settlePreview(Rect bounds) {
    setState(() {
      _isDraggingPreview = false;
      _previewOffset = _clampPreviewOffset(
        _previewOffset ?? Offset(bounds.right, bounds.bottom),
        bounds,
      );
    });
  }

  void _swapMainVideo() {
    setState(() {
      _localVideoOnMain = !_localVideoOnMain;
    });
  }

  void _switchCamera() {
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.switchCamera());
    } else {
      _retryRtcAfterFailure();
    }
  }

  void _toggleMic() {
    setState(() {
      _micEnabled = !_micEnabled;
    });
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.toggleMicrophone(enabled: _micEnabled));
    } else {
      _retryRtcAfterFailure();
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerEnabled = !_speakerEnabled;
    });
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.toggleSpeaker(enabled: _speakerEnabled));
    } else {
      _retryRtcAfterFailure();
    }
  }

  void _toggleCamera() {
    setState(() {
      _cameraEnabled = !_cameraEnabled;
    });
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.toggleCamera(enabled: _cameraEnabled));
      _sendMediaState();
    } else {
      _retryRtcAfterFailure();
    }
  }

  void _sendMediaState() {
    final controller = _signalingController;
    final targetDeviceId = _targetDeviceId;
    if (controller == null ||
        targetDeviceId == null ||
        targetDeviceId.isEmpty) {
      return;
    }
    controller.sendMediaState(
      callId: _callId,
      targetDeviceId: targetDeviceId,
      cameraEnabled: _cameraEnabled,
    );
  }

  void _retryRtcAfterFailure() {
    if (_initializing ||
        _statusOverride != '连接失败' ||
        _retryAfterFailureRequested) {
      return;
    }
    _retryAfterFailureRequested = true;
    unawaited(_startRtc());
  }

  Future<void> _startRtc() async {
    if (_initializing || _rtcJoined) {
      return;
    }
    final tokenClient = _resolveTokenClient();
    final userId = await _resolveUserId();
    final targetDeviceId = await _resolveTargetDeviceId();
    final signalingController = _resolveSignalingController();
    if (tokenClient == null ||
        userId == null ||
        targetDeviceId == null ||
        signalingController == null) {
      _logUnavailablePreconditions(
        tokenClient: tokenClient,
        userId: userId,
        targetDeviceId: targetDeviceId,
        signalingController: signalingController,
      );
      if (mounted) {
        setState(() {
          _statusOverride = '通话不可用';
        });
      }
      return;
    }
    _listenForRemoteHangup(signalingController);
    _initializing = true;
    if (mounted) {
      setState(() {
        _statusOverride = '正在连接阿里云视频通话';
      });
    }
    RtcAdapter? adapter;
    try {
      final token = await tokenClient.issueToken(
        channelId: _callId,
        userId: userId,
        role: RtcTokenRole.publisher,
        householdId: SyncService.instance?.settings.householdId,
        authToken: SyncService.instance?.settings.householdAuthToken,
      );
      adapter = _rtcAdapter ?? MethodChannelRtcAdapter();
      if (widget.rtcAdapter == null) {
        _ownedAdapter = adapter;
      }
      await adapter.initialize();
      if (_disposed) {
        await adapter.dispose();
        if (identical(_ownedAdapter, adapter)) {
          _ownedAdapter = null;
        }
        return;
      }
      await adapter.join(token.toJoinConfig(remoteUserId: targetDeviceId));
      if (_disposed) {
        await adapter.leave();
        await adapter.dispose();
        if (identical(_ownedAdapter, adapter)) {
          _ownedAdapter = null;
        }
        return;
      }
      _rtcJoined = true;
      _retryAfterFailureRequested = false;
      await adapter.toggleMicrophone(enabled: _micEnabled);
      await adapter.toggleSpeaker(enabled: _speakerEnabled);
      await adapter.toggleCamera(enabled: _cameraEnabled);
      _startCallTimer();
      if (widget.sendInviteOnJoin) {
        signalingController.sendInvite(
          callId: _callId,
          mode: widget.mode == RemoteVideoMode.watch
              ? RtcCallMode.watch
              : RtcCallMode.call,
          callerDeviceId: userId,
          targetDeviceId: targetDeviceId,
          sdp: 'ready',
        );
      }
      _sendMediaState();
      if (mounted) {
        setState(() {
          _statusOverride = null;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('[PetNoteRemoteVideo] start failed: $error');
      debugPrint('$stackTrace');
      if (mounted) {
        setState(() {
          _statusOverride = '连接失败';
        });
      }
      if (adapter != null) {
        await adapter.dispose();
        if (identical(_ownedAdapter, adapter)) {
          _ownedAdapter = null;
        }
      }
      _rtcJoined = false;
    } finally {
      _initializing = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _logUnavailablePreconditions({
    required RtcTokenClient? tokenClient,
    required String? userId,
    required String? targetDeviceId,
    required RtcSignalingController? signalingController,
  }) {
    final service = SyncService.instance;
    final devices = widget.devicesOverride ??
        service?.syncController?.devices.value ??
        const [];
    final deviceSummary = devices
        .map(
          (device) => '${device.deviceId}'
              '(role=${device.role},pet=${device.servedPetId ?? '-'},'
              'online=${device.online})',
        )
        .join(',');
    debugPrint(
      '[PetNoteRemoteVideo] unavailable '
      'tokenClient=${tokenClient != null} '
      'userId=${userId ?? '-'} '
      'targetDeviceId=${targetDeviceId ?? '-'} '
      'signaling=${signalingController != null} '
      'syncActive=${service?.isActive ?? false} '
      'serverUrl=${service?.settings.syncServerUrl ?? '-'} '
      'household=${service?.settings.householdId ?? '-'} '
      'role=${service?.settings.deviceRole.name ?? '-'} '
      'devices=${devices.length} '
      'deviceSummary=[$deviceSummary]',
    );
  }

  Future<String?> _resolveTargetDeviceId() async {
    final explicit = widget.targetDeviceId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final current = _targetDeviceId;
    if (current != null && current.isNotEmpty) {
      return current;
    }
    if (widget.devicesOverride != null) {
      return current;
    }
    final engine = SyncService.instance?.syncController;
    if (engine == null) {
      return current;
    }
    engine.requestDevices();
    final completer = Completer<String?>();
    VoidCallback? listener;
    Timer? timer;
    void complete(String? value) {
      if (completer.isCompleted) {
        return;
      }
      timer?.cancel();
      if (listener != null) {
        engine.devices.removeListener(listener);
      }
      completer.complete(value);
    }

    listener = () {
      final selected = _targetDeviceId;
      if (selected != null && selected.isNotEmpty) {
        complete(selected);
      }
    };
    engine.devices.addListener(listener);
    timer = Timer(_deviceDirectoryWaitTimeout, () => complete(_targetDeviceId));
    listener();
    return completer.future;
  }

  Future<void> _hangup() async {
    final navigator = Navigator.of(context);
    final controller = _signalingController;
    final targetDeviceId = _targetDeviceId;
    if (_rtcJoined &&
        controller != null &&
        targetDeviceId != null &&
        targetDeviceId.isNotEmpty) {
      controller.sendEnd(callId: _callId, targetDeviceId: targetDeviceId);
    }
    await _teardownRtc();
    await navigator.maybePop();
  }

  Future<void> _teardownRtc() async {
    _callTimer?.cancel();
    _callTimer = null;
    final adapter = _rtcAdapter;
    final wasJoined = _rtcJoined;
    _rtcJoined = false;
    if (adapter != null && wasJoined) {
      try {
        await adapter.leave();
      } finally {
        await adapter.dispose();
        if (identical(_ownedAdapter, adapter)) {
          _ownedAdapter = null;
        }
      }
    }
    _connectedAt = null;
    _callElapsed = Duration.zero;
  }

  void _startCallTimer() {
    _connectedAt = DateTime.now();
    _callElapsed = Duration.zero;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final connectedAt = _connectedAt;
      if (!mounted || connectedAt == null) {
        return;
      }
      setState(() {
        _callElapsed = DateTime.now().difference(connectedAt);
      });
    });
  }

  void _listenForRemoteHangup(RtcSignalingController signalingController) {
    _signalSubscription ??= signalingController.signals.listen((signal) {
      if (signal.callId != _callId) {
        return;
      }
      switch (signal) {
        case RtcCallEnd():
          unawaited(_handleRemoteHangup());
        case RtcCallMediaState(:final cameraEnabled):
          if (mounted) {
            setState(() {
              _remoteCameraEnabled = cameraEnabled;
            });
          }
        case _:
          break;
      }
    });
  }

  Future<void> _handleRemoteHangup() async {
    if (_disposed || !mounted) {
      return;
    }
    setState(() {
      _statusOverride = '已挂断';
    });
    await _teardownRtc();
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  RtcTokenClient? _resolveTokenClient() {
    if (widget.tokenClient != null) {
      return widget.tokenClient;
    }
    if (_ownedTokenClient != null) {
      return _ownedTokenClient;
    }
    final syncServerUrl = SyncService.instance?.settings.syncServerUrl;
    final baseUri = rtcTokenBaseUriFromSyncServerUrl(syncServerUrl);
    if (baseUri == null) {
      return null;
    }
    if (_ownedTokenClient != null && _ownedTokenClientBaseUri == baseUri) {
      return _ownedTokenClient;
    }
    _ownedTokenClient?.dispose();
    _ownedTokenClientBaseUri = baseUri;
    return _ownedTokenClient = RtcTokenClient(baseUri: baseUri);
  }

  RtcSignalingController? _resolveSignalingController() {
    if (widget.signalingController != null) {
      return widget.signalingController;
    }
    if (_ownedSignalingController != null) {
      return _ownedSignalingController;
    }
    final transport = SyncService.instance?.debugTransport;
    if (transport == null) {
      return null;
    }
    return _ownedSignalingController =
        RtcSignalingController(transport: transport);
  }

  Future<String?> _resolveUserId() async {
    final injected = widget.userId?.trim();
    if (injected != null && injected.isNotEmpty) {
      return injected;
    }
    final settings = SyncService.instance?.settings;
    if (settings == null) {
      return null;
    }
    return settings.ensureDeviceId();
  }
}

String _formatElapsed(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours <= 0) {
    return '$minutes:$seconds';
  }
  return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
}

Uri? rtcTokenBaseUriFromSyncServerUrl(String? syncServerUrl) {
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

String _newRtcCallId(RemoteVideoMode mode) {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final entropy = identityHashCode(Object()).toUnsigned(20).toRadixString(36);
  final modeSegment = mode == RemoteVideoMode.call ? 'c' : 'w';
  return 'rtc-$modeSegment-$timestamp-$entropy';
}

SyncedDeviceInfo? selectedRemoteVideoDevice({
  required Pet pet,
  required List<SyncedDeviceInfo> devices,
}) {
  final assignedDevices = devices.where(
    (device) => device.role == 'pet' && device.servedPetId == pet.id,
  );
  final unassignedDevices = devices.where(
    (device) => device.role == 'pet' && device.servedPetId == null,
  );
  final petDevices = [...assignedDevices, ...unassignedDevices];
  if (petDevices.isEmpty) {
    return null;
  }
  return petDevices.firstWhere(
    (device) => device.online,
    orElse: () => petDevices.first,
  );
}

class _RemoteVideoSurface extends StatelessWidget {
  const _RemoteVideoSurface({
    required this.title,
    required this.statusLabel,
    required this.petName,
    required this.remoteUserId,
    required this.isConnected,
    required this.feed,
    required this.localCameraEnabled,
    required this.remoteCameraEnabled,
  });

  final String title;
  final String statusLabel;
  final String petName;
  final String? remoteUserId;
  final bool isConnected;
  final _VideoFeed feed;
  final bool localCameraEnabled;
  final bool remoteCameraEnabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('remote_video_main_surface'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1C21), Color(0xFF0B0C0F)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isConnected && feed == _VideoFeed.local)
            _RtcVideoTile(
              feed: feed,
              localCameraEnabled: localCameraEnabled,
              remoteCameraEnabled: remoteCameraEnabled,
              child: const RtcVideoView.local(
                key: ValueKey('remote_video_main_local_view'),
              ),
            )
          else if (isConnected && remoteUserId != null)
            _RtcVideoTile(
              feed: feed,
              localCameraEnabled: localCameraEnabled,
              remoteCameraEnabled: remoteCameraEnabled,
              child: RtcVideoView.remote(
                key: const ValueKey('remote_video_main_remote_view'),
                remoteUserId: remoteUserId!,
              ),
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    size: 76,
                    color: Color(0xFF6F7684),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    statusLabel,
                    key: const ValueKey('remote_video_status_label'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '连接对象：$petName',
                    key: const ValueKey('remote_video_target_pet'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFC8CDD6),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.pet,
    required this.title,
    required this.statusLabel,
    required this.elapsedLabel,
  });

  final Pet pet;
  final String title;
  final String? statusLabel;
  final String? elapsedLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveStatusLabel = statusLabel?.trim();
    return Row(
      children: [
        _CallHeaderAvatar(pet: pet),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (effectiveStatusLabel != null &&
                  effectiveStatusLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  effectiveStatusLabel,
                  key: const ValueKey('remote_video_call_state_label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC8CDD6),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              if (elapsedLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  elapsedLabel!,
                  key: const ValueKey('remote_video_elapsed_label'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF9EA7B6),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CallHeaderAvatar extends StatelessWidget {
  const _CallHeaderAvatar({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    const radius = 20.0;
    return SizedBox(
      key: const ValueKey('remote_video_pet_avatar'),
      width: radius * 2,
      height: radius * 2,
      child: hasPetPhoto(pet.photoPath)
          ? PetPhotoAvatar(
              photoPath: pet.photoPath,
              fallbackText: petAvatarFallbackForPet(pet),
              radius: radius,
              backgroundColor: const Color(0xFF313641),
              foregroundColor: Colors.white,
            )
          : const CircleAvatar(
              radius: radius,
              backgroundColor: Color(0xFF313641),
              child: Icon(Icons.pets_rounded, color: Colors.white, size: 20),
            ),
    );
  }
}

class _FloatingVideoPreview extends StatelessWidget {
  const _FloatingVideoPreview({
    required this.feed,
    required this.remoteUserId,
    required this.isConnected,
    required this.localCameraEnabled,
    required this.remoteCameraEnabled,
    required this.onTap,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final _VideoFeed feed;
  final String? remoteUserId;
  final bool isConnected;
  final bool localCameraEnabled;
  final bool remoteCameraEnabled;
  final VoidCallback onTap;
  final GestureDragUpdateCallback onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('remote_video_local_preview'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanUpdate: onPanUpdate,
      onPanEnd: (_) => onPanEnd(),
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: _previewSize.width,
            height: _previewSize.height,
            decoration: BoxDecoration(
              color: const Color(0xFF242832),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isConnected && feed == _VideoFeed.local)
                  _RtcVideoTile(
                    feed: feed,
                    localCameraEnabled: localCameraEnabled,
                    remoteCameraEnabled: remoteCameraEnabled,
                    child: const RtcVideoView.local(
                      key: ValueKey('remote_video_preview_local_view'),
                    ),
                  )
                else if (isConnected && remoteUserId != null)
                  _RtcVideoTile(
                    feed: feed,
                    localCameraEnabled: localCameraEnabled,
                    remoteCameraEnabled: remoteCameraEnabled,
                    child: RtcVideoView.remote(
                      key: const ValueKey('remote_video_preview_remote_view'),
                      remoteUserId: remoteUserId!,
                    ),
                  )
                else
                  const ColoredBox(color: Color(0xFF171A21)),
                const ColoredBox(color: Color(0x11000000)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RtcVideoTile extends StatelessWidget {
  const _RtcVideoTile({
    required this.feed,
    required this.localCameraEnabled,
    required this.remoteCameraEnabled,
    required this.child,
  });

  final _VideoFeed feed;
  final bool localCameraEnabled;
  final bool remoteCameraEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showOverlay = switch (feed) {
      _VideoFeed.local => !localCameraEnabled,
      _VideoFeed.remote => !remoteCameraEnabled,
    };
    if (showOverlay) {
      return const _CameraOffOverlay(
        key: ValueKey('remote_video_camera_off_overlay'),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
      ],
    );
  }
}

class _CameraOffOverlay extends StatelessWidget {
  const _CameraOffOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x80000000),
      child: Center(
        child: Text(
          '摄像头已关闭',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.micEnabled,
    required this.speakerEnabled,
    required this.cameraEnabled,
    required this.onToggleMic,
    required this.onToggleSpeaker,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onHangup,
    required this.isBusy,
  });

  final bool micEnabled;
  final bool speakerEnabled;
  final bool cameraEnabled;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangup;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallControlButton(
          key: const ValueKey('remote_video_mic_button'),
          icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
          onPressed: onToggleMic,
        ),
        _CallControlButton(
          key: const ValueKey('remote_video_speaker_button'),
          icon: speakerEnabled
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          onPressed: onToggleSpeaker,
        ),
        _CallControlButton(
          key: const ValueKey('remote_video_camera_button'),
          icon: cameraEnabled
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          onPressed: onToggleCamera,
        ),
        _CallControlButton(
          key: const ValueKey('remote_video_switch_camera_button'),
          icon: Icons.cameraswitch_rounded,
          onPressed: onSwitchCamera,
        ),
        _CallControlButton(
          key: const ValueKey('remote_video_hangup_button'),
          icon: Icons.call_end_rounded,
          backgroundColor: const Color(0xFFE64E45),
          foregroundColor: Colors.white,
          onPressed: isBusy ? () {} : onHangup,
        ),
      ],
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0x26FFFFFF),
    this.foregroundColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 58,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}
