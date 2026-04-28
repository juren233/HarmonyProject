import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android data package file access performs document IO off main thread',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteDataPackageFileAccessBridge.kt',
    ).readAsStringSync();

    expect(source, contains('Executors.newSingleThreadExecutor()'));
    expect(source, contains('ioExecutor.execute'));
    expect(source, contains('activity.runOnUiThread'));
    expect(source, contains('finishPendingRequest'));
    expect(source, contains('close()'));
    expect(
      source.indexOf('ioExecutor.execute'),
      lessThan(source.indexOf('readPickedFile(uri)')),
    );
    expect(
      source.indexOf('ioExecutor.execute'),
      lessThan(source.indexOf('writeBackupFile(')),
    );
  });

  test('android backup export copies from a temp file path instead of raw JSON',
      () {
    final source = File(
      'android/app/src/main/kotlin/com/krustykrab/petnote/PetNoteDataPackageFileAccessBridge.kt',
    ).readAsStringSync();

    expect(source, contains('sourceFilePath'));
    expect(source, contains('File(sourceFilePath)'));
    expect(source, contains('input.copyTo(output)'));
    expect(source, isNot(contains('arguments?.get("rawJson")')));
    expect(source, isNot(contains('writer.write(rawJson)')));
  });

  test('ios backup import returns a local temp file path instead of raw JSON',
      () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('localFilePath'));
    expect(source, contains('copyItem(at: url'));
    expect(source, isNot(contains('String(contentsOf: url')));
    expect(source, isNot(contains('rawJson: rawJson')));
  });
}
