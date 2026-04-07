import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:petnote/state/petnote_store.dart';

typedef IosDockBuilder = Widget Function(
  BuildContext context,
  AppTab selectedTab,
  ValueChanged<AppTab> onTabSelected,
  VoidCallback onAddTap,
);

const _iosNativeDockViewType = 'petnote/ios_native_dock';
const _iosNativeDockCenterSymbolSize = 42.0;
const _iosNativeDockCenterSymbolCanvasOffset = 8.0;

bool supportsIosNativeDock(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

class IosNativeDockHost extends StatefulWidget {
  const IosNativeDockHost({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAddTap,
  });

  final AppTab selectedTab;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback onAddTap;

  @override
  State<IosNativeDockHost> createState() => _IosNativeDockHostState();
}

class _IosNativeDockHostState extends State<IosNativeDockHost> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IosNativeDockHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _syncSelectedTab();
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('ios_native_dock_host'),
      height: 140,
      child: UiKitView(
        viewType: _iosNativeDockViewType,
        creationParams: {
          'selectedTab': widget.selectedTab.name,
          'brightness': Theme.of(context).brightness.name,
          'centerSymbolSize': _iosNativeDockCenterSymbolSize,
          'centerSymbolCanvasOffset': _iosNativeDockCenterSymbolCanvasOffset,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('petnote/ios_native_dock_$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    _syncSelectedTab();
  }

  Future<void> _syncSelectedTab() async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod<void>(
          'setSelectedTab', widget.selectedTab.name);
    } on PlatformException {
      // Ignore transient sync failures while the native view initializes.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'tabSelected':
        final tab = appTabFromName(call.arguments as String?);
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

AppTab? appTabFromName(String? name) {
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
