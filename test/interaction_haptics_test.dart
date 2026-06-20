import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/interaction_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/interaction_haptics');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('playDeleteHoldRamp invokes native interaction haptics ramp', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelInteractionHaptics(channel: channel);
    await driver.playDeleteHoldRamp(durationMs: 560);

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'playDeleteHoldRamp');
    expect(recordedCall!.arguments, {'durationMs': 560});
  });

  test('stopDeleteHoldRamp invokes native interaction haptics stop', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelInteractionHaptics(channel: channel);
    await driver.stopDeleteHoldRamp();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'stopDeleteHoldRamp');
  });

  test('playDeleteConfirmImpact invokes native interaction haptics impact',
      () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelInteractionHaptics(channel: channel);
    await driver.playDeleteConfirmImpact();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'playDeleteConfirmImpact');
  });
}
