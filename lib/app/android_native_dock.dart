import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/state/petnote_store.dart';

const _androidLiquidGlassDockViewType = 'petnote/android_liquid_glass_dock';

@visibleForTesting
bool debugDisableAndroidLiquidGlassDock = false;

bool supportsAndroidLiquidGlassDock(TargetPlatform platform) {
  return platform == TargetPlatform.android &&
      !debugDisableAndroidLiquidGlassDock &&
      !Platform.environment.containsKey('FLUTTER_TEST');
}

class AndroidLiquidGlassDockHost extends StatefulWidget {
  const AndroidLiquidGlassDockHost({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAddTap,
    this.onFirstInteractionPrewarmed,
    this.shouldPrewarmFirstInteraction = false,
  });

  final AppTab selectedTab;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onAddTap;
  final VoidCallback? onFirstInteractionPrewarmed;
  final bool shouldPrewarmFirstInteraction;

  @override
  State<AndroidLiquidGlassDockHost> createState() =>
      _AndroidLiquidGlassDockHostState();
}

class _AndroidLiquidGlassDockHostState
    extends State<AndroidLiquidGlassDockHost> {
  static const _firstInteractionPrewarmRetryDelay = Duration(milliseconds: 120);

  MethodChannel? _channel;
  bool _hasRequestedFirstInteractionPrewarm = false;
  int _firstInteractionPrewarmEpoch = 0;

  @override
  void didUpdateWidget(covariant AndroidLiquidGlassDockHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _syncSelectedTab();
    }
    _syncBrightness();
    if (oldWidget.shouldPrewarmFirstInteraction &&
        !widget.shouldPrewarmFirstInteraction) {
      _resetFirstInteractionPrewarmState();
    }
    if (!oldWidget.shouldPrewarmFirstInteraction &&
        widget.shouldPrewarmFirstInteraction) {
      _maybeRequestFirstInteractionPrewarm();
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
    final dockHeight = 96 + viewPadding.bottom;
    return SizedBox(
      key: const ValueKey('android_liquid_glass_dock_host'),
      height: dockHeight,
      child: AndroidView(
        viewType: _androidLiquidGlassDockViewType,
        creationParams: {
          'selectedTab': widget.selectedTab.name,
          'brightness': Theme.of(context).brightness.name,
          'bottomInset': viewPadding.bottom,
          'shouldPrewarmFirstInteraction': widget.shouldPrewarmFirstInteraction,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('petnote/android_liquid_glass_dock_$viewId');
    _channel = channel;
    _resetFirstInteractionPrewarmState(syncNative: false);
    channel.setMethodCallHandler(_handleMethodCall);
    _syncSelectedTab();
    _syncBrightness();
    _maybeRequestFirstInteractionPrewarm();
  }

  Future<void> _syncSelectedTab() async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
        'setSelectedTab',
        widget.selectedTab.name,
      );
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _syncBrightness() async {
    final channel = _channel;
    if (channel == null || !mounted) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
        'setBrightness',
        Theme.of(context).brightness.name,
      );
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  Future<void> _maybeRequestFirstInteractionPrewarm() async {
    final channel = _channel;
    if (channel == null ||
        _hasRequestedFirstInteractionPrewarm ||
        !widget.shouldPrewarmFirstInteraction) {
      return;
    }
    try {
      await channel.invokeMethod<void>('prewarmFirstInteraction');
      _hasRequestedFirstInteractionPrewarm = true;
    } on PlatformException {
      _scheduleFirstInteractionPrewarmRetry();
    }
  }

  void _resetFirstInteractionPrewarmState({bool syncNative = true}) {
    _hasRequestedFirstInteractionPrewarm = false;
    _firstInteractionPrewarmEpoch += 1;
    if (syncNative) {
      _resetNativeFirstInteractionPrewarmState();
    }
  }

  Future<void> _resetNativeFirstInteractionPrewarmState() async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod<void>('resetFirstInteractionPrewarm');
    } on PlatformException {
      // 忽略原生视图初始化早期的瞬时同步失败。
    }
  }

  void _scheduleFirstInteractionPrewarmRetry() {
    final retryEpoch = _firstInteractionPrewarmEpoch;
    Future<void>.delayed(_firstInteractionPrewarmRetryDelay, () async {
      if (!mounted || retryEpoch != _firstInteractionPrewarmEpoch) {
        return;
      }
      await _maybeRequestFirstInteractionPrewarm();
    });
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'firstInteractionPrewarmed':
        _hasRequestedFirstInteractionPrewarm = true;
        widget.onFirstInteractionPrewarmed?.call();
        return;
      case 'tabSelected':
        final tab = _appTabFromName(call.arguments as String?);
        if (tab != null) {
          widget.onTabSelected(tab);
        }
        return;
      case 'addTapped':
        widget.onAddTap();
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
