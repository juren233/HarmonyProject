import 'package:flutter/services.dart';

abstract class InteractionHapticsDriver {
  Future<void> playDeleteHoldRamp({required int durationMs});

  Future<void> stopDeleteHoldRamp();

  Future<void> playDeleteConfirmImpact();
}

class MethodChannelInteractionHaptics implements InteractionHapticsDriver {
  MethodChannelInteractionHaptics({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/interaction_haptics';

  final MethodChannel _channel;

  @override
  Future<void> playDeleteHoldRamp({required int durationMs}) async {
    try {
      await _channel.invokeMethod<void>('playDeleteHoldRamp', {
        'durationMs': durationMs,
      });
    } on MissingPluginException {
      await _playDeleteHoldRampFallback();
    } on PlatformException {
      await _playDeleteHoldRampFallback();
    }
  }

  @override
  Future<void> stopDeleteHoldRamp() async {
    try {
      await _channel.invokeMethod<void>('stopDeleteHoldRamp');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<void> playDeleteConfirmImpact() async {
    try {
      await _channel.invokeMethod<void>('playDeleteConfirmImpact');
    } on MissingPluginException {
      await _playDeleteConfirmFallback();
    } on PlatformException {
      await _playDeleteConfirmFallback();
    }
  }

  Future<void> _playDeleteHoldRampFallback() async {
    try {
      await HapticFeedback.selectionClick();
    } on PlatformException {
      return;
    }
  }

  Future<void> _playDeleteConfirmFallback() async {
    try {
      await HapticFeedback.mediumImpact();
    } on PlatformException {
      return;
    }
  }
}
