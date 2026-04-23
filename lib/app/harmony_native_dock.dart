import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/state/petnote_store.dart';

const _harmonyNativeDockViewType = 'petnote/harmony_native_dock';

bool supportsHarmonyNativeDock(TargetPlatform platform) {
  return platform == TargetPlatform.ohos &&
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

  @override
  void didUpdateWidget(covariant HarmonyNativeDockHost oldWidget) {
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
      key: const ValueKey('harmony_native_dock_host'),
      height: dockHeight,
      child: OhosView(
        viewType: _harmonyNativeDockViewType,
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
    final channel = MethodChannel('petnote/harmony_native_dock_$viewId');
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
