import 'package:flutter/services.dart';
import 'package:petnote/logging/app_log_controller.dart';

enum NativePetPhotoPickerStatus {
  success,
  cancelled,
  error,
}

enum NativePetPhotoPickerErrorCode {
  cancelled,
  unavailable,
  invalidResponse,
  platformError,
}

class NativePetPhotoPickerResult {
  const NativePetPhotoPickerResult._({
    required this.status,
    this.localPath,
    this.errorCode,
    this.errorMessage,
  });

  const NativePetPhotoPickerResult.success({
    required String localPath,
  }) : this._(
          status: NativePetPhotoPickerStatus.success,
          localPath: localPath,
        );

  const NativePetPhotoPickerResult.cancelled()
      : this._(status: NativePetPhotoPickerStatus.cancelled);

  const NativePetPhotoPickerResult.error({
    required NativePetPhotoPickerErrorCode errorCode,
    required String errorMessage,
  }) : this._(
          status: NativePetPhotoPickerStatus.error,
          errorCode: errorCode,
          errorMessage: errorMessage,
        );

  final NativePetPhotoPickerStatus status;
  final String? localPath;
  final NativePetPhotoPickerErrorCode? errorCode;
  final String? errorMessage;

  bool get isSuccess => status == NativePetPhotoPickerStatus.success;
  bool get isCancelled => status == NativePetPhotoPickerStatus.cancelled;
}

class NativePetPhotoPickerBatchResult {
  const NativePetPhotoPickerBatchResult._({
    required this.status,
    this.localPaths = const <String>[],
    this.errorCode,
    this.errorMessage,
  });

  const NativePetPhotoPickerBatchResult.success({
    required List<String> localPaths,
  }) : this._(
          status: NativePetPhotoPickerStatus.success,
          localPaths: localPaths,
        );

  const NativePetPhotoPickerBatchResult.cancelled()
      : this._(status: NativePetPhotoPickerStatus.cancelled);

  const NativePetPhotoPickerBatchResult.error({
    required NativePetPhotoPickerErrorCode errorCode,
    required String errorMessage,
  }) : this._(
          status: NativePetPhotoPickerStatus.error,
          errorCode: errorCode,
          errorMessage: errorMessage,
        );

  final NativePetPhotoPickerStatus status;
  final List<String> localPaths;
  final NativePetPhotoPickerErrorCode? errorCode;
  final String? errorMessage;

  bool get isSuccess => status == NativePetPhotoPickerStatus.success;
  bool get isCancelled => status == NativePetPhotoPickerStatus.cancelled;
}

abstract class NativePetPhotoPicker {
  Future<NativePetPhotoPickerResult> pickPetPhoto();

  Future<NativePetPhotoPickerBatchResult> pickPetPhotos();

  Future<void> deletePetPhoto(String path);
}

class MethodChannelNativePetPhotoPicker implements NativePetPhotoPicker {
  MethodChannelNativePetPhotoPicker({
    MethodChannel? channel,
    this.appLogController,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/native_pet_photo_picker';

  final MethodChannel _channel;
  final AppLogController? appLogController;

  @override
  Future<NativePetPhotoPickerResult> pickPetPhoto() async {
    try {
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '调用原生宠物图片选择器',
        message: '开始打开系统相册选择宠物图片。',
      );
      final rawResponse = await _channel.invokeMethod<Object?>('pickPetPhoto');
      if (rawResponse is! Map<Object?, Object?>) {
        return const NativePetPhotoPickerResult.error(
          errorCode: NativePetPhotoPickerErrorCode.invalidResponse,
          errorMessage: '原生宠物图片选择器返回了无效数据。',
        );
      }
      final status = rawResponse['status'] as String?;
      switch (status) {
        case 'success':
          final localPath = rawResponse['localPath'];
          if (localPath is! String || localPath.isEmpty) {
            return const NativePetPhotoPickerResult.error(
              errorCode: NativePetPhotoPickerErrorCode.invalidResponse,
              errorMessage: '原生宠物图片选择器没有返回有效的本地路径。',
            );
          }
          appLogController?.info(
            category: AppLogCategory.nativeBridge,
            title: '原生宠物图片选择成功',
            message: '已返回本地图片路径。',
            details: localPath,
          );
          return NativePetPhotoPickerResult.success(localPath: localPath);
        case 'cancelled':
          appLogController?.warning(
            category: AppLogCategory.nativeBridge,
            title: '原生宠物图片选择取消',
            message: '用户取消了系统相册选择。',
          );
          return const NativePetPhotoPickerResult.cancelled();
        case 'error':
          final errorCode =
              _parseErrorCode(rawResponse['errorCode'] as String?);
          final errorMessage =
              rawResponse['errorMessage'] as String? ?? '原生宠物图片选择器当前不可用。';
          appLogController?.error(
            category: AppLogCategory.nativeBridge,
            title: '原生宠物图片选择失败',
            message: errorMessage,
            details: 'code: ${rawResponse['errorCode'] ?? ''}',
          );
          return NativePetPhotoPickerResult.error(
            errorCode: errorCode,
            errorMessage: errorMessage,
          );
        default:
          return const NativePetPhotoPickerResult.error(
            errorCode: NativePetPhotoPickerErrorCode.invalidResponse,
            errorMessage: '原生宠物图片选择器返回了未知状态。',
          );
      }
    } on MissingPluginException {
      return const NativePetPhotoPickerResult.error(
        errorCode: NativePetPhotoPickerErrorCode.unavailable,
        errorMessage: '当前平台暂未接入原生宠物图片选择器。',
      );
    } on PlatformException catch (error) {
      return NativePetPhotoPickerResult.error(
        errorCode: _parseErrorCode(error.code),
        errorMessage: error.message ?? '当前平台暂未接入原生宠物图片选择器。',
      );
    }
  }

  @override
  Future<NativePetPhotoPickerBatchResult> pickPetPhotos() async {
    try {
      appLogController?.info(
        category: AppLogCategory.nativeBridge,
        title: '调用原生宠物图片多选器',
        message: '开始打开系统相册批量选择记录图片。',
      );
      final rawResponse = await _channel.invokeMethod<Object?>('pickPetPhotos');
      if (rawResponse is! Map<Object?, Object?>) {
        return const NativePetPhotoPickerBatchResult.error(
          errorCode: NativePetPhotoPickerErrorCode.invalidResponse,
          errorMessage: '原生宠物图片选择器返回了无效数据。',
        );
      }
      final status = rawResponse['status'] as String?;
      switch (status) {
        case 'success':
          final localPaths = rawResponse['localPaths'];
          if (localPaths is! List ||
              localPaths.isEmpty ||
              localPaths.any((path) => path is! String || path.isEmpty)) {
            return const NativePetPhotoPickerBatchResult.error(
              errorCode: NativePetPhotoPickerErrorCode.invalidResponse,
              errorMessage: '原生宠物图片选择器没有返回有效的本地路径列表。',
            );
          }
          final parsedPaths = localPaths.cast<String>();
          appLogController?.info(
            category: AppLogCategory.nativeBridge,
            title: '原生宠物图片多选成功',
            message: '已返回 ${parsedPaths.length} 张本地图片路径。',
          );
          return NativePetPhotoPickerBatchResult.success(
            localPaths: parsedPaths,
          );
        case 'cancelled':
          appLogController?.warning(
            category: AppLogCategory.nativeBridge,
            title: '原生宠物图片多选取消',
            message: '用户取消了系统相册选择。',
          );
          return const NativePetPhotoPickerBatchResult.cancelled();
        case 'error':
          final errorCode =
              _parseErrorCode(rawResponse['errorCode'] as String?);
          final errorMessage =
              rawResponse['errorMessage'] as String? ?? '原生宠物图片选择器当前不可用。';
          appLogController?.error(
            category: AppLogCategory.nativeBridge,
            title: '原生宠物图片多选失败',
            message: errorMessage,
            details: 'code: ${rawResponse['errorCode'] ?? ''}',
          );
          return NativePetPhotoPickerBatchResult.error(
            errorCode: errorCode,
            errorMessage: errorMessage,
          );
        default:
          return const NativePetPhotoPickerBatchResult.error(
            errorCode: NativePetPhotoPickerErrorCode.invalidResponse,
            errorMessage: '原生宠物图片选择器返回了未知状态。',
          );
      }
    } on MissingPluginException {
      return const NativePetPhotoPickerBatchResult.error(
        errorCode: NativePetPhotoPickerErrorCode.unavailable,
        errorMessage: '当前平台暂未接入原生宠物图片选择器。',
      );
    } on PlatformException catch (error) {
      return NativePetPhotoPickerBatchResult.error(
        errorCode: _parseErrorCode(error.code),
        errorMessage: error.message ?? '当前平台暂未接入原生宠物图片选择器。',
      );
    }
  }

  @override
  Future<void> deletePetPhoto(String path) async {
    if (path.trim().isEmpty) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('deletePetPhoto', <String, Object?>{
        'path': path,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static NativePetPhotoPickerErrorCode _parseErrorCode(String? value) {
    return switch (value) {
      'cancelled' => NativePetPhotoPickerErrorCode.cancelled,
      'invalidResponse' => NativePetPhotoPickerErrorCode.invalidResponse,
      'platformError' => NativePetPhotoPickerErrorCode.platformError,
      _ => NativePetPhotoPickerErrorCode.unavailable,
    };
  }
}
