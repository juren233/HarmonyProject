import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/platform/petnote_app_directory.dart';
import 'package:petnote/state/petnote_store.dart';

const String petPhotoAttachmentsPayloadKey = 'petPhotoAttachments';
const String petPhotoAttachmentPayloadKey = 'petPhotoAttachment';
const int syncPhotoAttachmentMaxBytes = 3 * 1024 * 1024;

class SyncPhotoAttachmentException implements Exception {
  const SyncPhotoAttachmentException(this.message);

  final String message;

  @override
  String toString() => 'SyncPhotoAttachmentException: $message';
}

class SyncPhotoAttachment {
  const SyncPhotoAttachment({
    required this.petId,
    required this.fileName,
    required this.base64Data,
    this.blobId,
    this.sha256,
    this.sizeBytes,
  });

  final String petId;
  final String fileName;
  final String base64Data;
  final String? blobId;
  final String? sha256;
  final int? sizeBytes;

  Map<String, dynamic> toJson() {
    return {
      'petId': petId,
      'fileName': fileName,
      'base64Data': base64Data,
      if (blobId != null) 'blobId': blobId,
      if (sha256 != null) 'sha256': sha256,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
    };
  }

  factory SyncPhotoAttachment.fromJson(Map<String, dynamic> json) {
    final size = json['sizeBytes'];
    final sha = (json['sha256'] as String?)?.trim();
    return SyncPhotoAttachment(
      petId: json['petId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      base64Data: json['base64Data'] as String? ?? '',
      blobId: (json['blobId'] as String?)?.trim(),
      sha256: sha == null || sha.isEmpty ? null : sha,
      sizeBytes: size is num ? size.toInt() : null,
    );
  }
}

class SyncPhotoAttachmentCodec {
  const SyncPhotoAttachmentCodec({
    Future<String?> Function()? directoryLoader,
    int maxPhotoBytes = syncPhotoAttachmentMaxBytes,
  })  : _directoryLoader = directoryLoader,
        _maxPhotoBytes = maxPhotoBytes;

  final Future<String?> Function()? _directoryLoader;
  final int _maxPhotoBytes;

  Future<List<SyncPhotoAttachment>> collectFromState(
    PetNoteDataState state,
  ) async {
    final attachments = <SyncPhotoAttachment>[];
    final seenPaths = <String>{};
    for (final pet in state.pets) {
      final attachment = await collectForPet(pet, seenPaths: seenPaths);
      if (attachment != null) {
        attachments.add(attachment);
      }
    }
    return attachments;
  }

  Future<SyncPhotoAttachment?> collectForPet(
    Pet pet, {
    Set<String>? seenPaths,
  }) async {
    final photoPath = pet.photoPath?.trim();
    if (photoPath == null || photoPath.isEmpty) {
      return null;
    }
    if (seenPaths != null && !seenPaths.add(photoPath)) {
      return null;
    }
    final file = File(photoPath);
    final exists = await file.exists();
    if (!exists) {
      return null;
    }
    final length = await file.length();
    if (length <= 0 || length > _maxPhotoBytes) {
      return null;
    }
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    return SyncPhotoAttachment(
      petId: pet.id,
      fileName: _safeFileName(photoPath, pet.id),
      base64Data: base64Encode(bytes),
      blobId: 'sha256:$digest',
      sha256: digest,
      sizeBytes: bytes.length,
    );
  }

  Future<PetNoteDataState> applyToState(
    PetNoteDataState state,
    List<SyncPhotoAttachment> attachments,
  ) async {
    if (attachments.isEmpty || state.pets.isEmpty) {
      return state;
    }
    final pathByPetId = await _writeAttachments(attachments);
    final expectedPetIds = {
      for (final pet in state.pets)
        if (attachments.any((attachment) => attachment.petId == pet.id)) pet.id,
    };
    final missingPetIds = expectedPetIds.difference(pathByPetId.keys.toSet());
    if (missingPetIds.isNotEmpty) {
      throw SyncPhotoAttachmentException(
        '部分宠物头像附件未能写入本地：${missingPetIds.join(',')}',
      );
    }
    if (pathByPetId.isEmpty) {
      return state;
    }
    return PetNoteDataState(
      pets: [
        for (final pet in state.pets)
          _pathFor(pet, pathByPetId) == null
              ? pet
              : _copyPetWithPhotoPath(pet, _pathFor(pet, pathByPetId)),
      ],
      todos: state.todos,
      reminders: state.reminders,
      records: state.records,
    );
  }

  Future<Map<String, String>> _writeAttachments(
    List<SyncPhotoAttachment> attachments,
  ) async {
    final baseDirectory =
        await (_directoryLoader ?? PetNoteAppDirectory.load)();
    if (baseDirectory == null || baseDirectory.trim().isEmpty) {
      throw const SyncPhotoAttachmentException('本地应用目录不可用，无法写入同步头像');
    }
    final directory = Directory(
      _joinPath(baseDirectory.trim(), 'petnote_synced_pet_photos'),
    );
    await directory.create(recursive: true);
    final pathByPetId = <String, String>{};
    for (final attachment in attachments) {
      if (attachment.petId.isEmpty || attachment.base64Data.isEmpty) {
        continue;
      }
      final bytes = _decodeBytes(attachment.base64Data);
      if (!_isValidAttachmentBytes(attachment, bytes)) {
        throw SyncPhotoAttachmentException(
          '宠物头像附件校验失败：${attachment.petId}',
        );
      }
      final file = File(_joinPath(
        directory.path,
        '${_safeSegment(attachment.petId)}-${_safeFileName(attachment.fileName, attachment.petId)}',
      ));
      await file.writeAsBytes(bytes!, flush: true);
      pathByPetId[attachment.petId] = file.path;
    }
    return pathByPetId;
  }

  Uint8List? _decodeBytes(String value) {
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }

  bool _isValidAttachmentBytes(
    SyncPhotoAttachment attachment,
    Uint8List? bytes,
  ) {
    if (bytes == null || bytes.isEmpty || bytes.length > _maxPhotoBytes) {
      return false;
    }
    final expectedSize = attachment.sizeBytes;
    if (expectedSize != null && expectedSize != bytes.length) {
      return false;
    }
    final expectedHash = attachment.sha256;
    if (expectedHash != null &&
        expectedHash.isNotEmpty &&
        sha256.convert(bytes).toString() != expectedHash) {
      return false;
    }
    final expectedBlobId = attachment.blobId;
    if (expectedBlobId != null &&
        expectedBlobId.isNotEmpty &&
        expectedHash != null &&
        expectedHash.isNotEmpty &&
        expectedBlobId != 'sha256:$expectedHash') {
      return false;
    }
    return true;
  }
}

List<SyncPhotoAttachment> syncPhotoAttachmentsFromPayload(Object? rawValue) {
  if (rawValue is! List) {
    return const <SyncPhotoAttachment>[];
  }
  return rawValue
      .whereType<Map>()
      .map((item) => SyncPhotoAttachment.fromJson(
            Map<String, dynamic>.from(item),
          ))
      .where((item) => item.petId.isNotEmpty && item.base64Data.isNotEmpty)
      .toList(growable: false);
}

SyncPhotoAttachment? syncPhotoAttachmentFromPayload(Object? rawValue) {
  if (rawValue is! Map) {
    return null;
  }
  final attachment = SyncPhotoAttachment.fromJson(
    Map<String, dynamic>.from(rawValue),
  );
  if (attachment.petId.isEmpty || attachment.base64Data.isEmpty) {
    return null;
  }
  return attachment;
}

Pet _copyPetWithPhotoPath(Pet pet, String? photoPath) {
  return Pet(
    id: pet.id,
    name: pet.name,
    avatarText: pet.avatarText,
    photoPath: photoPath,
    type: pet.type,
    breed: pet.breed,
    sex: pet.sex,
    birthday: pet.birthday,
    ageLabel: pet.ageLabel,
    weightKg: pet.weightKg,
    neuterStatus: pet.neuterStatus,
    feedingPreferences: pet.feedingPreferences,
    allergies: pet.allergies,
    note: pet.note,
  );
}

String? _pathFor(Pet pet, Map<String, String> pathByPetId) {
  return pathByPetId[pet.id];
}

String _safeFileName(String rawPath, String fallbackId) {
  final fileName = rawPath
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.isNotEmpty)
      .lastOrNull
      ?.trim();
  if (fileName == null || fileName.isEmpty || fileName == '.') {
    return '${_safeSegment(fallbackId)}.jpg';
  }
  return _safeSegment(fileName);
}

String _joinPath(String directory, String fileName) {
  final separator = Platform.pathSeparator;
  if (directory.endsWith(separator)) {
    return '$directory$fileName';
  }
  return '$directory$separator$fileName';
}

String _safeSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'photo' : sanitized;
}
