import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/sync/sync_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/ai_secret_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('shared key 通过 method channel 保存、读取与删除', () async {
    final values = <String, String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'writeKey':
          final args = Map<String, Object?>.from(call.arguments as Map);
          values[args['configId']! as String] = args['value']! as String;
          return null;
        case 'readKey':
          final args = Map<String, Object?>.from(call.arguments as Map);
          return values[args['configId']];
        case 'deleteKey':
          final args = Map<String, Object?>.from(call.arguments as Map);
          values.remove(args['configId']);
          return null;
      }
      fail('未预期的 method channel 调用：${call.method}');
    });

    final store = MethodChannelSyncSecretStore(channel: channel);
    await store.saveSharedKey('base64-key');
    expect(await store.loadSharedKey(), 'base64-key');
    await store.deleteSharedKey();
    expect(await store.loadSharedKey(), isNull);
  });

  test('安全存储不可用时抛出可观察错误', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isAvailable') {
        return false;
      }
      return null;
    });

    final store = MethodChannelSyncSecretStore(channel: channel);
    expect(store.saveSharedKey('base64-key'),
        throwsA(isA<SyncSecretStoreException>()));
  });
}
