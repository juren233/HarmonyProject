import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef IosOverviewRangeButtonBuilder = Widget Function(
  BuildContext context,
  String label,
  Future<void> Function() onPressed,
);

const _iosOverviewRangeButtonViewType = 'petnote/ios_overview_range_button';

bool supportsIosNativeOverviewRangeButton(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

class IosNativeOverviewRangeButtonHost extends StatefulWidget {
  const IosNativeOverviewRangeButtonHost({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<IosNativeOverviewRangeButtonHost> createState() =>
      _IosNativeOverviewRangeButtonHostState();
}

class _IosNativeOverviewRangeButtonHostState
    extends State<IosNativeOverviewRangeButtonHost> {
  MethodChannel? _channel;
  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness != brightness) {
      _lastBrightness = brightness;
      _syncState();
    }
  }

  @override
  void didUpdateWidget(covariant IosNativeOverviewRangeButtonHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      _syncState();
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
      key: const ValueKey('ios-overview-range-button-host'),
      width: _estimatedWidthForLabel(widget.label),
      height: 40,
      child: UiKitView(
        viewType: _iosOverviewRangeButtonViewType,
        creationParams: {
          'label': widget.label,
          'brightness': Theme.of(context).brightness.name,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('petnote/ios_overview_range_button_$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    _syncState();
  }

  Future<void> _syncState() async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod<void>('updateState', {
        'label': widget.label,
        'brightness': Theme.of(context).brightness.name,
      });
    } on PlatformException {
      // Ignore transient sync failures while the native view initializes.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'pressed':
        await widget.onPressed();
      default:
        break;
    }
  }

  double _estimatedWidthForLabel(String label) {
    final characterCount = label.runes.length.clamp(2, 4);
    return (58 + characterCount * 18).toDouble();
  }
}
