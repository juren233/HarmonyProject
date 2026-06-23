import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_storage_models.dart';
import 'package:petnote/state/petnote_store.dart';
import 'package:petnote/sync/sync_photo_attachment.dart';

void main() {
  test('宠物头像附件生成稳定内容元数据', () async {
    final directory = Directory.systemTemp.createTempSync(
      'petnote-photo-metadata-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final photo = File('${directory.path}/strong.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final pet = _pet(photoPath: photo.path);

    final attachment =
        await const SyncPhotoAttachmentCodec().collectForPet(pet);

    expect(attachment, isNotNull);
    expect(attachment!.sizeBytes, 4);
    expect(
      attachment.sha256,
      '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
    );
    expect(
      attachment.blobId,
      'sha256:9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
    );
    expect(attachment.toJson()['base64Data'], 'AQIDBA==');
  });

  test('接收端拒绝 hash 或 size 不匹配的宠物头像附件', () async {
    final directory = Directory.systemTemp.createTempSync(
      'petnote-photo-apply-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final state = PetNoteDataState(
      pets: [_pet(photoPath: '/remote/source.jpg')],
      todos: const [],
      reminders: const [],
      records: const [],
    );
    final codec = SyncPhotoAttachmentCodec(
      directoryLoader: () async => directory.path,
    );

    final rejected = await codec.applyToState(
      state,
      const [
        SyncPhotoAttachment(
          petId: 'pet-1',
          fileName: 'bad.jpg',
          base64Data: 'AQIDBA==',
          sha256: 'bad-hash',
          sizeBytes: 4,
        ),
      ],
    );

    expect(rejected.pets.single.photoPath, '/remote/source.jpg');
    expect(_filesUnder(directory), isEmpty);

    final rejectedSize = await codec.applyToState(
      state,
      const [
        SyncPhotoAttachment(
          petId: 'pet-1',
          fileName: 'bad-size.jpg',
          base64Data: 'AQIDBA==',
          sha256:
              '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
          sizeBytes: 5,
        ),
      ],
    );

    expect(rejectedSize.pets.single.photoPath, '/remote/source.jpg');
    expect(_filesUnder(directory), isEmpty);
  });

  test('缺少内容元数据的旧宠物头像附件仍可兼容写入', () async {
    final directory = Directory.systemTemp.createTempSync(
      'petnote-photo-legacy-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final state = PetNoteDataState(
      pets: [_pet(photoPath: '/remote/source.jpg')],
      todos: const [],
      reminders: const [],
      records: const [],
    );
    final codec = SyncPhotoAttachmentCodec(
      directoryLoader: () async => directory.path,
    );

    final updated = await codec.applyToState(
      state,
      const [
        SyncPhotoAttachment(
          petId: 'pet-1',
          fileName: 'legacy.jpg',
          base64Data: 'AQIDBA==',
        ),
      ],
    );

    final localPath = updated.pets.single.photoPath;
    expect(localPath, isNot('/remote/source.jpg'));
    expect(localPath, isNotNull);
    expect(File(localPath!).readAsBytesSync(), [1, 2, 3, 4]);
  });
}

Pet _pet({required String photoPath}) {
  return Pet(
    id: 'pet-1',
    name: '强',
    avatarText: '强',
    photoPath: photoPath,
    type: PetType.dog,
    breed: '柯基',
    sex: '弟弟',
    birthday: '2025-01-01',
    ageLabel: '新加入',
    weightKg: 8,
    neuterStatus: PetNeuterStatus.unknown,
    feedingPreferences: '少食多餐',
    allergies: '无',
    note: '头像',
  );
}

List<File> _filesUnder(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .toList(growable: false);
}
