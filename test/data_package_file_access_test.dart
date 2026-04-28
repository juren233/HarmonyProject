import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/data/data_package_file_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/data_package_file_access');
  final log = <MethodCall>[];

  tearDown(() async {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pickBackupFile decodes successful native result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return <String, Object?>{
        'status': 'success',
        'displayName': 'backup.json',
        'rawJson': '{"hello":"world"}',
        'locationLabel': 'Files',
        'byteLength': 17,
      };
    });

    final access = MethodChannelDataPackageFileAccess(channel: channel);
    final picked = await access.pickBackupFile();

    expect(log.single.method, 'pickBackupFile');
    expect(picked?.displayName, 'backup.json');
    expect(picked?.rawJson, '{"hello":"world"}');
    expect(picked?.locationLabel, 'Files');
    expect(picked?.byteLength, 17);
  });

  test('pickBackupFile returns null when user cancels', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'status': 'cancelled',
        'errorCode': 'cancelled',
      };
    });

    final access = MethodChannelDataPackageFileAccess(channel: channel);
    final picked = await access.pickBackupFile();

    expect(picked, isNull);
  });

  test('saveBackupFile sends a temp file path instead of raw JSON', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      expect(arguments['rawJson'], isNull);
      final sourceFilePath = arguments['sourceFilePath'];
      expect(sourceFilePath, isA<String>());
      expect(File(sourceFilePath as String).readAsStringSync(),
          '{"hello":"world"}');
      return <String, Object?>{
        'status': 'success',
        'displayName': 'backup.json',
        'locationLabel': 'Files',
        'byteLength': 17,
      };
    });

    final access = MethodChannelDataPackageFileAccess(channel: channel);
    final saved = await access.saveBackupFile(
      suggestedFileName: 'backup.json',
      rawJson: '{"hello":"world"}',
    );

    expect(log.single.method, 'saveBackupFile');
    expect(saved?.displayName, 'backup.json');
    expect(saved?.byteLength, 17);
  });

  test('saveBackupFile maps native write failure into a typed exception',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'status': 'error',
        'errorCode': 'writeFailed',
        'errorMessage': 'no writable destination',
      };
    });

    final access = MethodChannelDataPackageFileAccess(channel: channel);

    expect(
      () => access.saveBackupFile(
        suggestedFileName: 'backup.json',
        rawJson: '{"hello":"world"}',
      ),
      throwsA(
        isA<DataPackageFileException>()
            .having((error) => error.code, 'code',
                DataPackageFileErrorCode.writeFailed)
            .having(
              (error) => error.message,
              'message',
              contains('no writable destination'),
            ),
      ),
    );
  });

  test('invalid native payload is treated as an invalid response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'bad-payload');

    final access = MethodChannelDataPackageFileAccess(channel: channel);

    expect(
      access.pickBackupFile,
      throwsA(
        isA<DataPackageFileException>().having(
          (error) => error.code,
          'code',
          DataPackageFileErrorCode.invalidResponse,
        ),
      ),
    );
  });
}
