import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/app/native_pet_photo_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/native_pet_photo_picker');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pickPetPhoto decodes successful native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickPetPhoto');
      return <String, Object?>{
        'status': 'success',
        'localPath': '/tmp/pet-photo.png',
      };
    });

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    final result = await picker.pickPetPhoto();

    expect(result.status, NativePetPhotoPickerStatus.success);
    expect(result.localPath, '/tmp/pet-photo.png');
  });

  test('pickPetPhotos decodes successful native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickPetPhotos');
      return <String, Object?>{
        'status': 'success',
        'localPaths': <String>[
          '/tmp/pet-photo-1.png',
          '/tmp/pet-photo-2.png',
        ],
      };
    });

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    final result = await picker.pickPetPhotos();

    expect(result.status, NativePetPhotoPickerStatus.success);
    expect(result.localPaths, <String>[
      '/tmp/pet-photo-1.png',
      '/tmp/pet-photo-2.png',
    ]);
  });

  test('pickPetPhotos maps malformed paths to invalid response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'status': 'success',
        'localPaths': <Object?>['/tmp/pet-photo-1.png', ''],
      };
    });

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    final result = await picker.pickPetPhotos();

    expect(result.status, NativePetPhotoPickerStatus.error);
    expect(result.errorCode, NativePetPhotoPickerErrorCode.invalidResponse);
  });

  test('pickPetPhoto returns cancelled when user dismisses picker', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'status': 'cancelled',
      };
    });

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    final result = await picker.pickPetPhoto();

    expect(result.status, NativePetPhotoPickerStatus.cancelled);
    expect(result.localPath, isNull);
  });

  test('pickPetPhoto maps malformed payload to invalid response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'bad-payload');

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    final result = await picker.pickPetPhoto();

    expect(result.status, NativePetPhotoPickerStatus.error);
    expect(result.errorCode, NativePetPhotoPickerErrorCode.invalidResponse);
  });

  test('pickPetPhoto maps platform exception to unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'unavailable',
        message: 'picker unavailable',
      );
    });

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    final result = await picker.pickPetPhoto();

    expect(result.status, NativePetPhotoPickerStatus.error);
    expect(result.errorCode, NativePetPhotoPickerErrorCode.unavailable);
    expect(result.errorMessage, contains('picker unavailable'));
  });

  test('deletePetPhoto forwards path to native channel', () async {
    Map<Object?, Object?>? capturedArguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'deletePetPhoto');
      capturedArguments = call.arguments as Map<Object?, Object?>?;
      return null;
    });

    final picker = MethodChannelNativePetPhotoPicker(channel: channel);
    await picker.deletePetPhoto('/tmp/pet-photo.png');

    expect(capturedArguments?['path'], '/tmp/pet-photo.png');
  });
}
