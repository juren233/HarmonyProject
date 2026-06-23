import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/native_weight_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/native_weight_picker');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pickWeight decodes successful native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickWeight');
      expect(call.arguments, isA<Map<dynamic, dynamic>>());
      return <String, Object?>{
        'status': 'success',
        'value': 6.8,
      };
    });

    final picker = MethodChannelNativeWeightPicker(channel: channel);
    final result = await picker.pickWeight(
      const NativeWeightPickerRequest(
        initialValue: 4.0,
        minWeightKg: 0.1,
        maxWeightKg: 80.0,
        stepKg: 0.1,
      ),
    );

    expect(result.status, NativeWeightPickerStatus.success);
    expect(result.value, 6.8);
  });

  test('pickWeight returns manual input when native sheet requests it',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'status': 'manualInput',
      };
    });

    final picker = MethodChannelNativeWeightPicker(channel: channel);
    final result = await picker.pickWeight(
      const NativeWeightPickerRequest(
        initialValue: 4.0,
        minWeightKg: 0.1,
        maxWeightKg: 80.0,
        stepKg: 0.1,
      ),
    );

    expect(result.status, NativeWeightPickerStatus.manualInput);
  });

  test('pickWeight maps malformed payload to invalid response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'bad-payload');

    final picker = MethodChannelNativeWeightPicker(channel: channel);
    final result = await picker.pickWeight(
      const NativeWeightPickerRequest(
        initialValue: 4.0,
        minWeightKg: 0.1,
        maxWeightKg: 80.0,
        stepKg: 0.1,
      ),
    );

    expect(result.status, NativeWeightPickerStatus.error);
    expect(result.errorCode, NativeWeightPickerErrorCode.invalidResponse);
  });
}
