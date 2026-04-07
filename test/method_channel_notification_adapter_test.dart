import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petnote/notifications/method_channel_notification_adapter.dart';
import 'package:petnote/notifications/notification_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('petnote/notifications');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('open notification settings maps native opened result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openNotificationSettings');
      return 'opened';
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.openNotificationSettings();

    expect(result, NotificationSettingsOpenResult.opened);
  });

  test('open notification settings maps native failed result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openNotificationSettings');
      return 'failed';
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.openNotificationSettings();

    expect(result, NotificationSettingsOpenResult.failed);
  });

  test('open notification settings returns unsupported when plugin is missing',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.openNotificationSettings();

    expect(result, NotificationSettingsOpenResult.unsupported);
  });
}
