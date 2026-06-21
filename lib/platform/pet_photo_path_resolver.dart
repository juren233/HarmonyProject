import 'dart:io';

import 'package:petnote/platform/petnote_app_directory.dart';

const String petPhotoDirectoryName = 'pet_photos';

class PetPhotoPathResolver {
  const PetPhotoPathResolver._();

  static String? _currentPetPhotoDirectoryPath;

  static Future<String?> loadAndCachePetPhotoDirectoryPath({
    Future<String?> Function()? appSupportDirectoryLoader,
  }) async {
    final baseDirectory =
        await (appSupportDirectoryLoader ?? PetNoteAppDirectory.load)();
    final directoryPath = petPhotoDirectoryPathFromAppSupport(baseDirectory);
    _currentPetPhotoDirectoryPath = directoryPath;
    return directoryPath;
  }

  static void debugSetCurrentPetPhotoDirectoryPath(String? directoryPath) {
    _currentPetPhotoDirectoryPath = _normalizeOptionalPath(directoryPath);
  }

  static String? resolveExistingPath(
    String? storedPath, {
    String? petPhotoDirectoryPath,
  }) {
    final path = _normalizeOptionalPath(storedPath);
    if (path == null) {
      return null;
    }
    if (_fileExists(path)) {
      return path;
    }
    final currentDirectory = _normalizeOptionalPath(petPhotoDirectoryPath) ??
        _currentPetPhotoDirectoryPath;
    if (currentDirectory == null || !_looksLikePetPhotoPath(path)) {
      return null;
    }
    final candidate = _joinPath(currentDirectory, _fileName(path));
    return _fileExists(candidate) ? candidate : null;
  }

  static String? relocateLegacyPath(
    String? storedPath, {
    required String? petPhotoDirectoryPath,
  }) {
    final path = _normalizeOptionalPath(storedPath);
    if (path == null || _fileExists(path)) {
      return null;
    }
    return resolveExistingPath(
      path,
      petPhotoDirectoryPath: petPhotoDirectoryPath,
    );
  }

  static bool shouldAttemptLegacyRelocation(String? storedPath) {
    final path = _normalizeOptionalPath(storedPath);
    if (path == null || _fileExists(path)) {
      return false;
    }
    return _looksLikePetPhotoPath(path);
  }

  static String? petPhotoDirectoryPathFromAppSupport(String? baseDirectory) {
    final base = _normalizeOptionalPath(baseDirectory);
    if (base == null) {
      return null;
    }
    return _joinPath(base, petPhotoDirectoryName);
  }

  static bool _looksLikePetPhotoPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').contains(petPhotoDirectoryName);
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? normalized : segments.last;
  }

  static String _joinPath(String directory, String fileName) {
    return '${directory.replaceAll(RegExp(r'[/\\]+$'), '')}'
        '${Platform.pathSeparator}$fileName';
  }

  static String? _normalizeOptionalPath(String? path) {
    final normalized = path?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
