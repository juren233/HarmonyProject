import 'package:flutter/services.dart';

enum NativeWeightPickerStatus {
  success,
  manualInput,
  cancelled,
  error,
}

enum NativeWeightPickerErrorCode {
  cancelled,
  unavailable,
  invalidResponse,
  platformError,
}

class NativeWeightPickerRequest {
  const NativeWeightPickerRequest({
    required this.initialValue,
    required this.minWeightKg,
    required this.maxWeightKg,
    required this.stepKg,
  });

  final double initialValue;
  final double minWeightKg;
  final double maxWeightKg;
  final double stepKg;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'initialValue': initialValue,
      'minWeightKg': minWeightKg,
      'maxWeightKg': maxWeightKg,
      'stepKg': stepKg,
    };
  }
}

class NativeWeightPickerResult {
  const NativeWeightPickerResult._({
    required this.status,
    this.value,
    this.errorCode,
    this.errorMessage,
  });

  const NativeWeightPickerResult.success({required double value})
      : this._(status: NativeWeightPickerStatus.success, value: value);

  const NativeWeightPickerResult.manualInput()
      : this._(status: NativeWeightPickerStatus.manualInput);

  const NativeWeightPickerResult.cancelled()
      : this._(status: NativeWeightPickerStatus.cancelled);

  const NativeWeightPickerResult.error({
    required NativeWeightPickerErrorCode errorCode,
    required String errorMessage,
  }) : this._(
          status: NativeWeightPickerStatus.error,
          errorCode: errorCode,
          errorMessage: errorMessage,
        );

  final NativeWeightPickerStatus status;
  final double? value;
  final NativeWeightPickerErrorCode? errorCode;
  final String? errorMessage;

  bool get isSuccess => status == NativeWeightPickerStatus.success;
}

abstract class NativeWeightPicker {
  Future<NativeWeightPickerResult> pickWeight(
    NativeWeightPickerRequest request,
  );
}

class MethodChannelNativeWeightPicker implements NativeWeightPicker {
  MethodChannelNativeWeightPicker({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/native_weight_picker';

  final MethodChannel _channel;

  @override
  Future<NativeWeightPickerResult> pickWeight(
    NativeWeightPickerRequest request,
  ) async {
    try {
      final rawResponse = await _channel.invokeMethod<Object?>(
        'pickWeight',
        request.toJson(),
      );
      if (rawResponse is! Map<Object?, Object?>) {
        return const NativeWeightPickerResult.error(
          errorCode: NativeWeightPickerErrorCode.invalidResponse,
          errorMessage: '原生体重选择器返回了无效数据。',
        );
      }
      final status = rawResponse['status'] as String?;
      switch (status) {
        case 'success':
          final value = rawResponse['value'];
          if (value is! num) {
            return const NativeWeightPickerResult.error(
              errorCode: NativeWeightPickerErrorCode.invalidResponse,
              errorMessage: '原生体重选择器没有返回有效体重。',
            );
          }
          return NativeWeightPickerResult.success(value: value.toDouble());
        case 'manualInput':
          return const NativeWeightPickerResult.manualInput();
        case 'cancelled':
          return const NativeWeightPickerResult.cancelled();
        case 'error':
          final errorCode =
              _parseErrorCode(rawResponse['errorCode'] as String?);
          final errorMessage =
              rawResponse['errorMessage'] as String? ?? '原生体重选择器当前不可用。';
          return NativeWeightPickerResult.error(
            errorCode: errorCode,
            errorMessage: errorMessage,
          );
        default:
          return const NativeWeightPickerResult.error(
            errorCode: NativeWeightPickerErrorCode.invalidResponse,
            errorMessage: '原生体重选择器返回了未知状态。',
          );
      }
    } on MissingPluginException {
      return const NativeWeightPickerResult.error(
        errorCode: NativeWeightPickerErrorCode.unavailable,
        errorMessage: '当前平台暂未接入原生体重选择器。',
      );
    } on PlatformException catch (error) {
      return NativeWeightPickerResult.error(
        errorCode: NativeWeightPickerErrorCode.unavailable,
        errorMessage: error.message ?? '当前平台暂未接入原生体重选择器。',
      );
    }
  }

  static NativeWeightPickerErrorCode _parseErrorCode(String? value) {
    return switch (value) {
      'cancelled' => NativeWeightPickerErrorCode.cancelled,
      'invalidResponse' => NativeWeightPickerErrorCode.invalidResponse,
      'platformError' => NativeWeightPickerErrorCode.platformError,
      _ => NativeWeightPickerErrorCode.unavailable,
    };
  }
}
