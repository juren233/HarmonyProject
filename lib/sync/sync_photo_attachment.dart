import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/platform/petnote_app_directory.dart';
import 'package:petnote/state/petnote_store.dart';

const String petPhotoAttachmentsPayloadKey = 'petPhotoAttachments';
const String petPhotoAttachmentPayloadKey = 'petPhotoAttachment';

class SyncPhotoAttachment {
  const SyncPhotoAttachment({
    required this.petId,
    required this.fileName,
    required this.base64Data,
  });

  final String petId;
  final String fileName;
  final String base64Data;

  Map<String, dynamic> toJson() {
    return {
      'petId': petId,
      'fileName': fileName,
      'base64Data': base64Data,
    };
  }

  factory SyncPhotoAttachment.fromJson(Map<String, dynamic> json) {
    return SyncPhotoAttachment(
      petId: json['petId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      base64Data: json['base64Data'] as String? ?? '',
    );
  }
}

class SyncPhotoAttachmentCodec {
  const SyncPhotoAttachmentCodec({
    Future<String?> Function()? directoryLoader,
    int maxPhotoBytes = 3 * 1024 * 1024,
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
    return SyncPhotoAttachment(
      petId: pet.id,
      fileName: _safeFileName(photoPath, pet.id),
      base64Data: base64Encode(bytes),
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
      return const <String, String>{};
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
      if (bytes == null || bytes.isEmpty || bytes.length > _maxPhotoBytes) {
        continue;
      }
      final file = File(_joinPath(
        directory.path,
        '${_safeSegment(attachment.petId)}-${_safeFileName(attachment.fileName, attachment.petId)}',
      ));
      await file.writeAsBytes(bytes, flush: true);
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
