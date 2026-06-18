import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/app/harmony_ohos_view.dart';
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
    this.followSystemTheme = true,
  });

  final AppTab selectedTab;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onAddTap;

  // 主题偏好为“跟随设备”时必须让原生侧保持 COLOR_MODE_NOT_SET，
  // 否则应用颜色模式被钉死后 ThemeMode.system 不再跟随系统明暗。
  final bool followSystemTheme;

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
  // Cache the last synced follow-system flag to detect preference changes.
  bool? _lastSyncedFollowSystemTheme;
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
    if (widget.followSystemTheme != _lastSyncedFollowSystemTheme) {
      _syncFollowSystemTheme(widget.followSystemTheme);
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
        child: HarmonyOhosView(
          viewType: _harmonyNativeDockViewType,
          layoutDirection: Directionality.of(context),
          creationParams: <String, Object?>{
            'selectedTab': widget.selectedTab.name,
            'brightness': Theme.of(context).brightness.name,
            'followSystemTheme': widget.followSystemTheme,
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
    _lastSyncedFollowSystemTheme = null;
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

  Future<void> _syncFollowSystemTheme(bool followSystemTheme) async {
    final channel = _channel;
    if (channel == null || !mounted) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
        'setThemeFollowsSystem',
        followSystemTheme,
      );
      if (mounted) {
        _lastSyncedFollowSystemTheme = followSystemTheme;
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
