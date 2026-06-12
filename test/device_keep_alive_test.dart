import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/platform/device_keep_alive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/keep_alive');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('保活方法通过同一 method channel 下发', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    final keepAlive = DeviceKeepAlive(channel: channel);
    await keepAlive.setKeepScreenOn(true);
    await keepAlive.startBackgroundKeepAlive();
    await keepAlive.stopBackgroundKeepAlive();

    expect(calls.map((call) => call.method), [
      'setKeepScreenOn',
      'startBackgroundKeepAlive',
      'stopBackgroundKeepAlive',
    ]);
    expect(calls.first.arguments, {'enabled': true});
  });

  test('平台缺失或拒绝时不阻塞看板', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'denied');
    });

    final keepAlive = DeviceKeepAlive(channel: channel);
    await keepAlive.setKeepScreenOn(true);
    await keepAlive.startBackgroundKeepAlive();
    await keepAlive.stopBackgroundKeepAlive();
  });
}
