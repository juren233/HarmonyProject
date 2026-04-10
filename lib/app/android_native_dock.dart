import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/state/petnote_store.dart';

const _androidLiquidGlassDockViewType = 'petnote/android_liquid_glass_dock';

bool supportsAndroidLiquidGlassDock(TargetPlatform platform) {
  return platform == TargetPlatform.android &&
      !Platform.environment.containsKey('FLUTTER_TEST');
}

class AndroidLiquidGlassDockHost extends StatefulWidget {
  const AndroidLiquidGlassDockHost({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAddTap,
  });

  final AppTab selectedTab;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onAddTap;

  @override
  State<AndroidLiquidGlassDockHost> createState() =>
      _AndroidLiquidGlassDockHostState();
}

class _AndroidLiquidGlassDockHostState
    extends State<AndroidLiquidGlassDockHost> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant AndroidLiquidGlassDockHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _syncSelectedTab();
    }
    _syncBrightness();
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
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('petnote/android_liquid_glass_dock_$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    _syncSelectedTab();
    _syncBrightness();
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

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'tabSelected':
        final tab = _appTabFromName(call.arguments as String?);
        if (tab != null) {
          widget.onTabSelected(tab);
        }
      case 'addTapped':
        widget.onAddTap();
      default:
        break;
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
