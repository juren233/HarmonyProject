import 'package:flutter/services.dart';

class DeviceKeepAlive {
  DeviceKeepAlive({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/keep_alive';

  final MethodChannel _channel;

  Future<void> setKeepScreenOn(bool enabled) async {
    await _invoke('setKeepScreenOn', {'enabled': enabled});
  }

  Future<void> startBackgroundKeepAlive() async {
    await _invoke('startBackgroundKeepAlive');
  }

  Future<void> stopBackgroundKeepAlive() async {
    await _invoke('stopBackgroundKeepAlive');
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
