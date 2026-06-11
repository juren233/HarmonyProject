import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/state/petnote_store.dart';

const _harmonyNativeDockViewType = 'petnote/harmony_native_dock';

// Height of the dock visuals (floating panel + breathing room) excluding
// the device-specific bottom safe-area inset. Must stay in sync with the
// native side: TAB_BAR_HEIGHT (78) + TAB_BAR_BOTTOM_MARGIN (6) + shadow
// headroom (12).
const _dockHostBaseHeight = 96.0;

bool supportsHarmonyNativeDock(TargetPlatform platform) {
  return platform.name == 'ohos' &&
      !Platform.environment.containsKey('FLUTTER_TEST');
}

class HarmonyNativeDockHost extends StatefulWidget {
  const HarmonyNativeDockHost({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAddTap,
  });

  final AppTab selectedTab;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onAddTap;

  @override
  State<HarmonyNativeDockHost> createState() => _HarmonyNativeDockHostState();
}

class _HarmonyNativeDockHostState extends State<HarmonyNativeDockHost> {
  MethodChannel? _channel;
  // Track the last tab we pushed to native side to suppress redundant echoes.
  // The OpenHarmony native dock echoes `tabSelected` back in response to
  // `setSelectedTab`, which can arrive during Flutter's build phase and cause
  // assertion failures (owner!._debugCurrentBuildTarget == this).
  AppTab? _lastSyncedTab;
  // Cache the last synced brightness to avoid redundant platform channel calls.
  Brightness? _lastSyncedBrightness;
  // Cache the last synced bottom inset to detect runtime changes.
  double? _lastSyncedBottomInset;
  // Bottom safe-area inset measured natively from the window avoid areas
  // (gesture indicator / 3-button nav bar) and reported back via the
  // `bottomInsetMeasured` channel call. Preferred over MediaQuery once known.
  double? _nativeMeasuredBottomInset;

  @override
  void didUpdateWidget(covariant HarmonyNativeDockHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      // Defer _syncSelectedTab to a post-frame callback. Sending the platform
      // channel message during build can cause the OpenHarmony native dock to
      // echo `tabSelected` back mid-build, which triggers setState → assertion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncSelectedTab();
        }
      });
    }
    _syncEnvironment();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fires when MediaQuery (nav-mode toggle, fold posture) or Theme changes,
    // which didUpdateWidget alone would miss.
    _syncEnvironment();
  }

  void _syncEnvironment() {
    // Capture inherited values synchronously BEFORE the async calls to avoid
    // registering InheritedWidget dependencies inside a fire-and-forget
    // async body (which can cause _depends.isEmpty assertion failures).
    final brightness = Theme.of(context).brightness;
    if (brightness != _lastSyncedBrightness) {
      _syncBrightness(brightness);
    }
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    if (bottomInset != _lastSyncedBottomInset) {
      _syncBottomInset(bottomInset);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    // Anchor to the real bottom safe area (gesture indicator / 3-button nav
    // bar). The native side measures the window avoid areas itself and
    // reports back via `bottomInsetMeasured`; until that arrives, Flutter's
    // viewPadding (fed by the same avoid areas through the OHOS embedder)
    // is used as the initial estimate.
    final effectiveBottomInset =
        math.max(viewPadding.bottom, _nativeMeasuredBottomInset ?? 0.0);
    assert(() {
      debugPrint('[PetNote] viewPadding.bottom=${viewPadding.bottom}, '
          'nativeMeasured=$_nativeMeasuredBottomInset, '
          'effectiveBottomInset=$effectiveBottomInset');
      return true;
    }());
    final dockHeight = _dockHostBaseHeight + effectiveBottomInset;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17),
      child: SizedBox(
        key: const ValueKey('harmony_native_dock_host'),
        height: dockHeight,
        child: _HarmonyOhosView(
          viewType: _harmonyNativeDockViewType,
          layoutDirection: Directionality.of(context),
          creationParams: <String, Object?>{
            'selectedTab': widget.selectedTab.name,
            'brightness': Theme.of(context).brightness.name,
            'bottomInset': effectiveBottomInset,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    // Clear old channel handler if the platform view is being re-created.
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('petnote/harmony_native_dock_$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    // The native view starts fresh — invalidate sync caches so the deferred
    // _syncEnvironment below pushes the current state to it.
    _lastSyncedBrightness = null;
    _lastSyncedBottomInset = null;
    // Defer all sync calls to a post-frame callback to avoid triggering
    // platform channel messages during the platform view creation build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncSelectedTab();
        _syncEnvironment();
      }
    });
  }

  Future<void> _syncSelectedTab() async {
    final channel = _channel;
    if (channel == null || !mounted) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
        'setSelectedTab',
        widget.selectedTab.name,
      );
      // Only update _lastSyncedTab AFTER the await succeeds to prevent a
      // race condition: if the user rapidly switches tabs, a stale echo
      // for a previous tab would not be suppressed because _lastSyncedTab
      // was optimistically set before the platform channel round-trip.
      if (mounted) {
        _lastSyncedTab = widget.selectedTab;
      }
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _syncBrightness(Brightness brightness) async {
    final channel = _channel;
    if (channel == null || !mounted) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
        'setBrightness',
        brightness.name,
      );
      if (mounted) {
        _lastSyncedBrightness = brightness;
      }
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _syncBottomInset(double bottomInset) async {
    final channel = _channel;
    if (channel == null || !mounted) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
        'setBottomInset',
        bottomInset,
      );
      if (mounted) {
        _lastSyncedBottomInset = bottomInset;
      }
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'tabSelected':
        final tab = _appTabFromName(call.arguments as String?);
        if (tab != null && tab != _lastSyncedTab) {
          _lastSyncedTab = tab;
          if (mounted) {
            widget.onTabSelected(tab);
          }
        }
        return;
      case 'addTapped':
        widget.onAddTap();
        return;
      case 'bottomInsetMeasured':
        final inset = (call.arguments as num?)?.toDouble();
        if (inset != null && inset != _nativeMeasuredBottomInset) {
          _nativeMeasuredBottomInset = inset;
          // May arrive while a frame is in progress on the OHOS embedder —
          // defer the rebuild to the end of the frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
        return;
      default:
        return;
    }
  }
}

// Texture-based platform view embedding. Hybrid composition
// (initExpensiveOhosView / createForPlatformViewLayer) is NOT usable with
// this flutter_ohos version: the embedder has no onDisplayPlatformView /
// initializePlatformViewIfNeeded path, so a platform-view layer is created
// but never attached to the window tree and the dock simply never renders.
class _HarmonyOhosView extends StatelessWidget {
  const _HarmonyOhosView({
    required this.viewType,
    this.onPlatformViewCreated,
    this.layoutDirection,
    this.creationParams,
    this.creationParamsCodec,
  });

  final String viewType;
  final PlatformViewCreatedCallback? onPlatformViewCreated;
  final TextDirection? layoutDirection;
  final dynamic creationParams;
  final MessageCodec<dynamic>? creationParamsCodec;

  @override
  Widget build(BuildContext context) {
    final resolvedDirection = layoutDirection ?? Directionality.of(context);
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (
        BuildContext context,
        PlatformViewController controller,
      ) {
        return _HarmonyOhosTextureSurface(
          controller: controller as _HarmonyOhosTextureController,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        return _HarmonyOhosTextureController(
          viewId: params.id,
          viewType: params.viewType,
          layoutDirection: resolvedDirection,
          creationParams: creationParams,
          creationParamsCodec: creationParamsCodec,
          onPlatformViewCreated: (int viewId) {
            params.onPlatformViewCreated(viewId);
            onPlatformViewCreated?.call(viewId);
          },
        );
      },
    );
  }
}

class _HarmonyOhosTextureSurface extends StatelessWidget {
  const _HarmonyOhosTextureSurface({
    required this.controller,
  });

  final _HarmonyOhosTextureController controller;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: controller.dispatchPointerEvent,
      onPointerMove: controller.dispatchPointerEvent,
      onPointerUp: controller.dispatchPointerEvent,
      onPointerCancel: controller.dispatchPointerEvent,
      child: Texture(textureId: controller.textureId),
    );
  }
}

class _HarmonyOhosTextureController extends PlatformViewController {
  _HarmonyOhosTextureController({
    required this.viewId,
    required String viewType,
    required TextDirection layoutDirection,
    required void Function(int) onPlatformViewCreated,
    dynamic creationParams,
    MessageCodec<dynamic>? creationParamsCodec,
  })  : _viewType = viewType,
        _layoutDirection = layoutDirection,
        _onPlatformViewCreated = onPlatformViewCreated,
        _creationParams = creationParams == null
            ? null
            : _HarmonyCreationParams(creationParams, creationParamsCodec!);

  static const int _actionDown = 0;
  static const int _actionUp = 1;
  static const int _actionMove = 2;
  static const int _actionCancel = 3;
  static const int _actionPointerDown = 5;
  static const int _actionPointerUp = 6;
  static const int _layoutDirectionLtr = 0;
  static const int _layoutDirectionRtl = 1;

  @override
  final int viewId;

  final String _viewType;
  final void Function(int) _onPlatformViewCreated;
  final _HarmonyCreationParams? _creationParams;
  final _HarmonyOhosMotionEventConverter _motionEventConverter =
      _HarmonyOhosMotionEventConverter();
  TextDirection _layoutDirection;
  _HarmonyOhosViewLifecycleState _state =
      _HarmonyOhosViewLifecycleState.waitingForCreate;
  int? _textureId;

  int get textureId => _textureId!;

  @override
  bool get awaitingCreation =>
      _state == _HarmonyOhosViewLifecycleState.waitingForCreate;

  bool get isCreated => _state == _HarmonyOhosViewLifecycleState.created;

  @override
  Future<void> create({Size? size, Offset? position}) async {
    if (_state != _HarmonyOhosViewLifecycleState.waitingForCreate ||
        size == null ||
        size.isEmpty) {
      return;
    }
    _state = _HarmonyOhosViewLifecycleState.creating;

    final args = <String, dynamic>{
      'id': viewId,
      'viewType': _viewType,
      'direction': _getDirection(_layoutDirection),
      'width': size.width,
      'height': size.height,
      if (position != null) 'left': position.dx,
      if (position != null) 'top': position.dy,
    };
    final creationParams = _creationParams;
    if (creationParams != null) {
      final byteData = creationParams.codec.encodeMessage(creationParams.data)!;
      args['params'] = Uint8List.view(
        byteData.buffer,
        0,
        byteData.lengthInBytes,
      );
    }

    final textureId =
        await SystemChannels.platform_views.invokeMethod<int>('create', args);
    _textureId = textureId;
    _state = _HarmonyOhosViewLifecycleState.created;
    _onPlatformViewCreated(viewId);
  }

  @override
  Future<void> clearFocus() {
    if (!isCreated) {
      return Future<void>.value();
    }
    return SystemChannels.platform_views
        .invokeMethod<void>('clearFocus', viewId);
  }

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {
    if (event is PointerHoverEvent) {
      if (event.kind == PointerDeviceKind.mouse) {
        await SystemChannels.platform_views.invokeMethod<void>('hover', viewId);
      }
      return;
    }

    if (event is PointerDownEvent) {
      _motionEventConverter.handlePointerDownEvent(event);
    }

    _motionEventConverter.updatePointerPositions(event);
    final motionEvent = _motionEventConverter.toOhosMotionEvent(event);

    if (event is PointerUpEvent) {
      _motionEventConverter.handlePointerUpEvent(event);
    } else if (event is PointerCancelEvent) {
      _motionEventConverter.handlePointerCancelEvent(event);
    }

    if (motionEvent == null) {
      return;
    }
    await SystemChannels.platform_views.invokeMethod<dynamic>(
      'touch',
      motionEvent.toList(viewId),
    );
  }

  @override
  Future<void> dispose() async {
    if (_state == _HarmonyOhosViewLifecycleState.creating ||
        _state == _HarmonyOhosViewLifecycleState.created) {
      await SystemChannels.platform_views.invokeMethod<void>(
        'dispose',
        <String, dynamic>{
          'id': viewId,
          'hybrid': false,
        },
      );
    }
    _state = _HarmonyOhosViewLifecycleState.disposed;
  }

  Future<void> setLayoutDirection(TextDirection layoutDirection) async {
    if (_layoutDirection == layoutDirection) {
      return;
    }
    _layoutDirection = layoutDirection;
    if (_state == _HarmonyOhosViewLifecycleState.waitingForCreate) {
      return;
    }
    await SystemChannels.platform_views.invokeMethod<void>(
      'setDirection',
      <String, dynamic>{
        'id': viewId,
        'direction': _getDirection(layoutDirection),
      },
    );
  }

  static int _getDirection(TextDirection direction) {
    switch (direction) {
      case TextDirection.ltr:
        return _layoutDirectionLtr;
      case TextDirection.rtl:
        return _layoutDirectionRtl;
    }
  }

  static int pointerAction(int pointerId, int action) {
    return ((pointerId << 8) & 0xff00) | (action & 0xff);
  }
}

enum _HarmonyOhosViewLifecycleState {
  waitingForCreate,
  creating,
  created,
  disposed,
}

class _HarmonyCreationParams {
  const _HarmonyCreationParams(this.data, this.codec);

  final dynamic data;
  final MessageCodec<dynamic> codec;
}

class _HarmonyOhosMotionEventConverter {
  final Map<int, _HarmonyOhosPointerCoords> _pointerPositions =
      <int, _HarmonyOhosPointerCoords>{};
  final Map<int, _HarmonyOhosPointerProperties> _pointerProperties =
      <int, _HarmonyOhosPointerProperties>{};
  final Set<int> _usedPointerIds = <int>{};

  int? _downTimeMillis;

  void handlePointerDownEvent(PointerDownEvent event) {
    if (_pointerProperties.isEmpty) {
      _downTimeMillis = event.timeStamp.inMilliseconds;
    }
    var pointerId = 0;
    while (_usedPointerIds.contains(pointerId)) {
      pointerId++;
    }
    _usedPointerIds.add(pointerId);
    _pointerProperties[event.pointer] = _propertiesFor(event, pointerId);
  }

  void updatePointerPositions(PointerEvent event) {
    final position = event.localPosition;
    _pointerPositions[event.pointer] = _HarmonyOhosPointerCoords(
      orientation: event.orientation,
      pressure: event.pressure,
      size: event.size,
      toolMajor: event.radiusMajor,
      toolMinor: event.radiusMinor,
      touchMajor: event.radiusMajor,
      touchMinor: event.radiusMinor,
      x: position.dx,
      y: position.dy,
    );
  }

  void handlePointerUpEvent(PointerUpEvent event) {
    _remove(event.pointer);
  }

  void handlePointerCancelEvent(PointerCancelEvent event) {
    _remove(event.pointer);
  }

  _HarmonyOhosMotionEvent? toOhosMotionEvent(PointerEvent event) {
    final pointers = _pointerPositions.keys.toList();
    final pointerIndex = pointers.indexOf(event.pointer);
    final pointerCount = pointers.length;

    const batchedPointerFlag = 1;
    if (event.platformData == batchedPointerFlag ||
        (_isSinglePointerAction(event) && pointerIndex < pointerCount - 1)) {
      return null;
    }

    final int action;
    if (event is PointerDownEvent) {
      action = pointerCount == 1
          ? _HarmonyOhosTextureController._actionDown
          : _HarmonyOhosTextureController.pointerAction(
              pointerIndex,
              _HarmonyOhosTextureController._actionPointerDown,
            );
    } else if (event is PointerUpEvent) {
      action = pointerCount == 1
          ? _HarmonyOhosTextureController._actionUp
          : _HarmonyOhosTextureController.pointerAction(
              pointerIndex,
              _HarmonyOhosTextureController._actionPointerUp,
            );
    } else if (event is PointerMoveEvent) {
      action = _HarmonyOhosTextureController._actionMove;
    } else if (event is PointerCancelEvent) {
      action = _HarmonyOhosTextureController._actionCancel;
    } else {
      return null;
    }

    return _HarmonyOhosMotionEvent(
      downTime: _downTimeMillis!,
      eventTime: event.timeStamp.inMilliseconds,
      action: action,
      pointerCount: pointerCount,
      pointerProperties: pointers
          .map<_HarmonyOhosPointerProperties>(
            (int key) => _pointerProperties[key]!,
          )
          .toList(),
      pointerCoords: pointers
          .map<_HarmonyOhosPointerCoords>(
            (int key) => _pointerPositions[key]!,
          )
          .toList(),
      metaState: 0,
      buttonState: 0,
      xPrecision: 1.0,
      yPrecision: 1.0,
      deviceId: 0,
      edgeFlags: 0,
      source: 0,
      flags: 0,
      motionEventId: event.embedderId,
    );
  }

  bool _isSinglePointerAction(PointerEvent event) {
    return event is! PointerDownEvent && event is! PointerUpEvent;
  }

  void _remove(int pointer) {
    _pointerPositions.remove(pointer);
    final properties = _pointerProperties.remove(pointer);
    if (properties != null) {
      _usedPointerIds.remove(properties.id);
    }
    if (_pointerProperties.isEmpty) {
      _downTimeMillis = null;
    }
  }

  _HarmonyOhosPointerProperties _propertiesFor(
    PointerEvent event,
    int pointerId,
  ) {
    final toolType = switch (event.kind) {
      PointerDeviceKind.touch ||
      PointerDeviceKind.trackpad =>
        _HarmonyOhosPointerProperties.toolTypeFinger,
      PointerDeviceKind.mouse => _HarmonyOhosPointerProperties.toolTypeMouse,
      PointerDeviceKind.stylus => _HarmonyOhosPointerProperties.toolTypeStylus,
      PointerDeviceKind.invertedStylus =>
        _HarmonyOhosPointerProperties.toolTypeEraser,
      PointerDeviceKind.unknown =>
        _HarmonyOhosPointerProperties.toolTypeUnknown,
    };
    return _HarmonyOhosPointerProperties(id: pointerId, toolType: toolType);
  }
}

class _HarmonyOhosMotionEvent {
  const _HarmonyOhosMotionEvent({
    required this.downTime,
    required this.eventTime,
    required this.action,
    required this.pointerCount,
    required this.pointerProperties,
    required this.pointerCoords,
    required this.metaState,
    required this.buttonState,
    required this.xPrecision,
    required this.yPrecision,
    required this.deviceId,
    required this.edgeFlags,
    required this.source,
    required this.flags,
    required this.motionEventId,
  });

  final int downTime;
  final int eventTime;
  final int action;
  final int pointerCount;
  final List<_HarmonyOhosPointerProperties> pointerProperties;
  final List<_HarmonyOhosPointerCoords> pointerCoords;
  final int metaState;
  final int buttonState;
  final double xPrecision;
  final double yPrecision;
  final int deviceId;
  final int edgeFlags;
  final int source;
  final int flags;
  final int motionEventId;

  List<dynamic> toList(int viewId) {
    return <dynamic>[
      viewId,
      downTime,
      eventTime,
      action,
      pointerCount,
      pointerProperties.map<List<int>>((item) => item.toList()).toList(),
      pointerCoords.map<List<double>>((item) => item.toList()).toList(),
      metaState,
      buttonState,
      xPrecision,
      yPrecision,
      deviceId,
      edgeFlags,
      source,
      flags,
      motionEventId,
    ];
  }
}

class _HarmonyOhosPointerProperties {
  const _HarmonyOhosPointerProperties({
    required this.id,
    required this.toolType,
  });

  static const int toolTypeUnknown = 0;
  static const int toolTypeFinger = 1;
  static const int toolTypeStylus = 2;
  static const int toolTypeMouse = 3;
  static const int toolTypeEraser = 4;

  final int id;
  final int toolType;

  List<int> toList() => <int>[id, toolType];
}

class _HarmonyOhosPointerCoords {
  const _HarmonyOhosPointerCoords({
    required this.orientation,
    required this.pressure,
    required this.size,
    required this.toolMajor,
    required this.toolMinor,
    required this.touchMajor,
    required this.touchMinor,
    required this.x,
    required this.y,
  });

  final double orientation;
  final double pressure;
  final double size;
  final double toolMajor;
  final double toolMinor;
  final double touchMajor;
  final double touchMinor;
  final double x;
  final double y;

  List<double> toList() {
    return <double>[
      orientation,
      pressure,
      size,
      toolMajor,
      toolMinor,
      touchMajor,
      touchMinor,
      x,
      y,
    ];
  }
}

AppTab? _appTabFromName(String? name) {
  if (name == null) {
    return null;
  }
  for (final tab in AppTab.values) {
    if (tab.name == name) {
      return tab;
    }
  }
  return null;
}
