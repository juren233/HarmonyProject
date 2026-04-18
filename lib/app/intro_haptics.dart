import 'package:flutter/services.dart';

abstract class IntroHapticsDriver {
  Future<void> playIntroLaunchContinuous();

  Future<void> stopIntroLaunchContinuous();

  Future<void> playIntroToOnboardingContinuous();

  Future<void> stopIntroToOnboardingContinuous();

  Future<void> playIntroPrimaryButtonTap();
}

class MethodChannelIntroHaptics implements IntroHapticsDriver {
  MethodChannelIntroHaptics({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/intro_haptics';

  final MethodChannel _channel;

  @override
  Future<void> playIntroLaunchContinuous() async {
    try {
      await _channel.invokeMethod<void>('playIntroLaunchContinuous');
    } on MissingPluginException {
      // Ignore platforms without the native bridge.
    } on PlatformException {
      // Ignore transient haptics failures so intro animation stays smooth.
    }
  }

  @override
  Future<void> stopIntroLaunchContinuous() async {
    try {
      await _channel.invokeMethod<void>('stopIntroLaunchContinuous');
    } on MissingPluginException {
      // Ignore platforms without the native bridge.
    } on PlatformException {
      // Ignore transient haptics failures so intro animation stays smooth.
    }
  }

  @override
  Future<void> playIntroToOnboardingContinuous() async {
    try {
      await _channel.invokeMethod<void>('playIntroToOnboardingContinuous');
    } on MissingPluginException {
      // Ignore platforms without the native bridge.
    } on PlatformException {
      // Ignore transient haptics failures so intro animation stays smooth.
    }
  }

  @override
  Future<void> stopIntroToOnboardingContinuous() async {
    try {
      await _channel.invokeMethod<void>('stopIntroToOnboardingContinuous');
    } on MissingPluginException {
      // Ignore platforms without the native bridge.
    } on PlatformException {
      // Ignore transient haptics failures so intro animation stays smooth.
    }
  }

  @override
  Future<void> playIntroPrimaryButtonTap() async {
    try {
      await _channel.invokeMethod<void>('playIntroPrimaryButtonTap');
    } on MissingPluginException {
      // Ignore platforms without the native bridge.
    } on PlatformException {
      // Ignore transient haptics failures so intro button clicks stay smooth.
    }
  }
}
