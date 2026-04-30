import 'dart:io';

import 'package:flutter/services.dart';
import 'package:petnote/platform/petnote_app_directory.dart';

enum DataPackageFileErrorCode {
  cancelled,
  unavailable,
  readFailed,
  writeFailed,
  invalidResponse,
}

class PickedDataPackageFile {
  const PickedDataPackageFile({
    required this.displayName,
    required this.rawJson,
    required this.locationLabel,
    required this.byteLength,
  });

  final String displayName;
  final String rawJson;
  final String locationLabel;
  final int byteLength;
}

class SavedDataPackageFile {
  const SavedDataPackageFile({
    required this.displayName,
    required this.locationLabel,
    required this.byteLength,
  });

  final String displayName;
  final String locationLabel;
  final int byteLength;
}

class DataPackageFileException implements Exception {
  const DataPackageFileException(this.code, this.message);

  final DataPackageFileErrorCode code;
  final String message;

  @override
  String toString() => 'DataPackageFileException($code, $message)';
}

abstract class DataPackageFileAccess {
  Future<PickedDataPackageFile?> pickBackupFile();

  Future<SavedDataPackageFile?> saveBackupFile({
    required String suggestedFileName,
    required String rawJson,
  });
}

class MethodChannelDataPackageFileAccess implements DataPackageFileAccess {
  MethodChannelDataPackageFileAccess({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'petnote/data_package_file_access';

  final MethodChannel _channel;

  @override
  Future<PickedDataPackageFile?> pickBackupFile() async {
    final payload = await _invoke('pickBackupFile');
    if (payload == null) {
      return null;
    }
    final rawJson = await _readPickedJson(payload);
    return PickedDataPackageFile(
      displayName: _requireString(payload, 'displayName'),
      rawJson: rawJson,
      locationLabel: _requireString(payload, 'locationLabel'),
      byteLength: _requireInt(payload, 'byteLength'),
    );
  }

  @override
  Future<SavedDataPackageFile?> saveBackupFile({
    required String suggestedFileName,
    required String rawJson,
  }) async {
    final sourceFile = await _writeExportTempFile(
      suggestedFileName: suggestedFileName,
      rawJson: rawJson,
    );
    try {
      final payload = await _invoke(
        'saveBackupFile',
        arguments: <String, Object?>{
          'suggestedFileName': suggestedFileName,
          'sourceFilePath': sourceFile.path,
        },
      );
      if (payload == null) {
        return null;
      }
      return SavedDataPackageFile(
        displayName: _requireString(payload, 'displayName'),
        locationLabel: _requireString(payload, 'locationLabel'),
        byteLength: _requireInt(payload, 'byteLength'),
      );
    } finally {
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }
  }

  Future<Map<Object?, Object?>?> _invoke(
    String method, {
    Map<String, Object?>? arguments,
  }) async {
    try {
      final rawResponse =
          await _channel.invokeMethod<Object?>(method, arguments);
      if (rawResponse is! Map<Object?, Object?>) {
        throw const DataPackageFileException(
          DataPackageFileErrorCode.invalidResponse,
          'Native file access returned an invalid payload.',
        );
      }
      final status = rawResponse['status'] as String?;
      switch (status) {
        case 'success':
          return rawResponse;
        case 'cancelled':
          return null;
        case 'error':
          throw DataPackageFileException(
            _parseErrorCode(rawResponse['errorCode'] as String?),
            rawResponse['errorMessage'] as String? ?? '文件操作失败。',
          );
        default:
          throw const DataPackageFileException(
            DataPackageFileErrorCode.invalidResponse,
            'Native file access returned an unknown status.',
          );
      }
    } on MissingPluginException {
      throw const DataPackageFileException(
        DataPackageFileErrorCode.unavailable,
        '当前平台暂未接入系统文件管理器。',
      );
    } on PlatformException catch (error) {
      throw DataPackageFileException(
        DataPackageFileErrorCode.unavailable,
        error.message ?? '系统文件管理器当前不可用。',
      );
    }
  }

  static String _requireString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw DataPackageFileException(
      DataPackageFileErrorCode.invalidResponse,
      'Native file access did not return a valid $key.',
    );
  }

  static int _requireInt(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw DataPackageFileException(
      DataPackageFileErrorCode.invalidResponse,
      'Native file access did not return a valid $key.',
    );
  }

  static Future<String> _readPickedJson(Map<Object?, Object?> payload) async {
    final rawJson = payload['rawJson'];
    if (rawJson is String && rawJson.isNotEmpty) {
      return rawJson;
    }
    final localFilePath = payload['localFilePath'];
    if (localFilePath is String && localFilePath.trim().isNotEmpty) {
      final file = File(localFilePath);
      try {
        return await file.readAsString();
      } finally {
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
    throw const DataPackageFileException(
      DataPackageFileErrorCode.invalidResponse,
      'Native file access returned no readable backup content.',
    );
  }

  static Future<File> _writeExportTempFile({
    required String suggestedFileName,
    required String rawJson,
  }) async {
    final baseDirectory =
        await PetNoteAppDirectory.load() ?? Directory.systemTemp.path;
    final directory = Directory(
      '$baseDirectory${Platform.pathSeparator}petnote_exports',
    );
    await directory.create(recursive: true);
    final safeFileName =
        suggestedFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final fileName =
        safeFileName.isEmpty ? 'petnote-backup.json' : safeFileName;
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${DateTime.now().microsecondsSinceEpoch}_$fileName',
    );
    return file.writeAsString(rawJson);
  }

  static DataPackageFileErrorCode _parseErrorCode(String? value) {
    return switch (value) {
      'cancelled' => DataPackageFileErrorCode.cancelled,
      'readFailed' => DataPackageFileErrorCode.readFailed,
      'writeFailed' => DataPackageFileErrorCode.writeFailed,
      'invalidResponse' => DataPackageFileErrorCode.invalidResponse,
      _ => DataPackageFileErrorCode.unavailable,
    };
  }
}
