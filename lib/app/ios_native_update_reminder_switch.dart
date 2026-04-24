import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const iosNativeUpdateReminderSwitchViewType =
    'petnote/ios_update_reminder_switch';

class IosNativeUpdateReminderSwitchHost extends StatefulWidget {
  const IosNativeUpdateReminderSwitchHost({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<IosNativeUpdateReminderSwitchHost> createState() =>
      _IosNativeUpdateReminderSwitchHostState();
}

class _IosNativeUpdateReminderSwitchHostState
    extends State<IosNativeUpdateReminderSwitchHost> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IosNativeUpdateReminderSwitchHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
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
      width: 51,
      height: 31,
      child: UiKitView(
        viewType: iosNativeUpdateReminderSwitchViewType,
        creationParams: {'value': widget.value},
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel(
      'petnote/ios_update_reminder_switch_$viewId',
    );
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
        'value': widget.value,
      });
    } on PlatformException {
      // 原生视图初始化过程中的瞬时同步失败不影响下一次状态同步。
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'changed':
        final value = call.arguments;
        if (value is bool) {
          widget.onChanged(value);
        }
      default:
        break;
    }
  }
}
