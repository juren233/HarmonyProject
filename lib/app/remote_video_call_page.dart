import 'dart:async';

import 'package:flutter/material.dart';
import 'package:petnote/app/remote_video_entry.dart';
import 'package:petnote/rtc/method_channel_rtc_adapter.dart';
import 'package:petnote/rtc/rtc_adapter.dart';
import 'package:petnote/rtc/rtc_call_models.dart';
import 'package:petnote/rtc/rtc_token_client.dart';
import 'package:petnote/rtc/rtc_signaling_controller.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_service.dart';
import 'package:petnote_sync_protocol/petnote_sync_protocol.dart';

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

class _RemoteVideoCallPageState extends State<RemoteVideoCallPage> {
  bool _initializing = false;
  bool _rtcJoined = false;
  bool _disposed = false;
  bool _micEnabled = true;
  bool _speakerEnabled = true;
  bool _cameraEnabled = true;
  String? _statusOverride;
  RtcAdapter? _ownedAdapter;
  RtcTokenClient? _ownedTokenClient;
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
          SyncService.instance?.ownerEngine?.devices.value ??
          const [],
    )?.deviceId;
  }

  RtcAdapter? get _rtcAdapter => widget.rtcAdapter ?? _ownedAdapter;

  RtcSignalingController? get _signalingController =>
      widget.signalingController ?? _ownedSignalingController;

  @override
  void initState() {
    super.initState();
    _resolvedCallId = widget.callId ??
        'rtc-${widget.pet.id}-${widget.mode.name}-'
            '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_startRtc());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _callTimer?.cancel();
    unawaited(_signalSubscription?.cancel());
    unawaited(_teardownRtc());
    _ownedTokenClient?.dispose();
    unawaited(_ownedSignalingController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectedDevice = selectedRemoteVideoDevice(
      pet: widget.pet,
      devices: widget.devicesOverride ??
          SyncService.instance?.ownerEngine?.devices.value ??
          const [],
    );
    final statusLabel = connectedDevice == null
        ? '未配对宠物端'
        : '${connectedDevice.name} ${connectedDevice.online ? '在线' : '离线'}';
    final title = widget.mode == RemoteVideoMode.call ? '视频通话' : '先看看它';
    final callStateLabel = _statusOverride ?? '发起中';
    final surfaceStatus = _statusOverride ?? statusLabel;

    return Scaffold(
      backgroundColor: const Color(0xFF101114),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _RemoteVideoSurface(
                title: title,
                statusLabel: surfaceStatus,
                petName: widget.pet.name,
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              right: 18,
              child: _CallHeader(
                title: title,
                statusLabel: callStateLabel,
                elapsedLabel:
                    _connectedAt == null ? null : _formatElapsed(_callElapsed),
              ),
            ),
            Positioned(
              right: 18,
              bottom: 128,
              child: const _LocalPreview(),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 22,
              child: _CallControls(
                micEnabled: _micEnabled,
                speakerEnabled: _speakerEnabled,
                cameraEnabled: _cameraEnabled,
                onToggleMic: _toggleMic,
                onToggleSpeaker: _toggleSpeaker,
                onToggleCamera: _toggleCamera,
                onHangup: () => unawaited(_hangup()),
                isBusy: _initializing,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleMic() {
    setState(() {
      _micEnabled = !_micEnabled;
    });
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.toggleMicrophone(enabled: _micEnabled));
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerEnabled = !_speakerEnabled;
    });
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.toggleSpeaker(enabled: _speakerEnabled));
    }
  }

  void _toggleCamera() {
    setState(() {
      _cameraEnabled = !_cameraEnabled;
    });
    if (_rtcJoined) {
      unawaited(_rtcAdapter?.toggleCamera(enabled: _cameraEnabled));
    }
  }

  Future<void> _startRtc() async {
    if (_initializing || _rtcJoined) {
      return;
    }
    final tokenClient = _resolveTokenClient();
    final userId = await _resolveUserId();
    final targetDeviceId = _targetDeviceId;
    final signalingController = _resolveSignalingController();
    if (tokenClient == null ||
        userId == null ||
        targetDeviceId == null ||
        signalingController == null) {
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
      await adapter.join(token.toJoinConfig());
      if (_disposed) {
        await adapter.leave();
        await adapter.dispose();
        if (identical(_ownedAdapter, adapter)) {
          _ownedAdapter = null;
        }
        return;
      }
      _rtcJoined = true;
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
      if (mounted) {
        setState(() {
          _statusOverride = '阿里云视频通话已连接';
        });
      }
    } catch (error) {
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
    } finally {
      _initializing = false;
      if (mounted) {
        setState(() {});
      }
    }
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
      if (signal is! RtcCallEnd || signal.callId != _callId) {
        return;
      }
      unawaited(_handleRemoteHangup());
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
  });

  final String title;
  final String statusLabel;
  final String petName;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1C21), Color(0xFF0B0C0F)],
        ),
      ),
      child: Center(
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
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.title,
    required this.statusLabel,
    required this.elapsedLabel,
  });

  final String title;
  final String statusLabel;
  final String? elapsedLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: Color(0xFF313641),
          child: Icon(Icons.pets_rounded, color: Colors.white, size: 20),
        ),
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
              const SizedBox(height: 2),
              Text(
                statusLabel,
                key: const ValueKey('remote_video_call_state_label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFC8CDD6),
                      fontWeight: FontWeight.w600,
                    ),
              ),
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

class _LocalPreview extends StatelessWidget {
  const _LocalPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('remote_video_local_preview'),
      width: 96,
      height: 142,
      decoration: BoxDecoration(
        color: const Color(0xFF242832),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: const Icon(
        Icons.person_rounded,
        color: Color(0xFFB7BEC9),
        size: 34,
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
    required this.onHangup,
    required this.isBusy,
  });

  final bool micEnabled;
  final bool speakerEnabled;
  final bool cameraEnabled;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleCamera;
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
