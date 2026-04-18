import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/intro_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/intro_haptics');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('playIntroLaunchContinuous invokes native intro haptics start',
      () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelIntroHaptics(channel: channel);
    await driver.playIntroLaunchContinuous();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'playIntroLaunchContinuous');
  });

  test('stopIntroLaunchContinuous invokes native intro haptics stop', () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelIntroHaptics(channel: channel);
    await driver.stopIntroLaunchContinuous();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'stopIntroLaunchContinuous');
  });

  test(
      'playIntroToOnboardingContinuous invokes native onboarding haptics start',
      () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelIntroHaptics(channel: channel);
    await driver.playIntroToOnboardingContinuous();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'playIntroToOnboardingContinuous');
  });

  test('stopIntroToOnboardingContinuous invokes native onboarding haptics stop',
      () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelIntroHaptics(channel: channel);
    await driver.stopIntroToOnboardingContinuous();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'stopIntroToOnboardingContinuous');
  });

  test('playIntroPrimaryButtonTap invokes native intro button haptics',
      () async {
    MethodCall? recordedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    final driver = MethodChannelIntroHaptics(channel: channel);
    await driver.playIntroPrimaryButtonTap();

    expect(recordedCall, isNotNull);
    expect(recordedCall!.method, 'playIntroPrimaryButtonTap');
  });
}
