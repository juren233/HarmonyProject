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

  test(
      'request permission only records prompt handling from explicit native flag',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestPermission');
      return <String, Object?>{
        'state': 'denied',
        'promptHandled': true,
      };
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.requestPermission();

    expect(result.state, NotificationPermissionState.denied);
    expect(result.promptHandledSystemDialog, isTrue);
  });

  test('request permission keeps prompt unhandled when native omits flag',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestPermission');
      return <String, Object?>{
        'state': 'denied',
      };
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.requestPermission();

    expect(result.state, NotificationPermissionState.denied);
    expect(result.promptHandledSystemDialog, isFalse);
  });

  test('request permission does not infer prompt handling from legacy string',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestPermission');
      return 'denied';
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.requestPermission();

    expect(result.state, NotificationPermissionState.denied);
    expect(result.promptHandledSystemDialog, isFalse);
  });

  test('has handled permission prompt maps native true result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'hasHandledPermissionPrompt');
      return true;
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.hasHandledPermissionPrompt();

    expect(result, isTrue);
  });

  test('has handled permission prompt returns false when plugin is missing',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.hasHandledPermissionPrompt();

    expect(result, isFalse);
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

  test('open exact alarm settings maps native opened result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openExactAlarmSettings');
      return 'opened';
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.openExactAlarmSettings();

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

  test('get capabilities maps native exact alarm status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getCapabilities');
      return <String, Object?>{
        'exactAlarmStatus': 'unavailable',
        'maxScheduledNotificationCount': 30,
      };
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.getCapabilities();

    expect(result.exactAlarmStatus, NotificationExactAlarmStatus.unavailable);
    expect(result.maxScheduledNotificationCount, 30);
  });

  test('schedule local notification forwards event schedule payload to native', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scheduleLocalNotification');
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      expect(arguments['scheduledAtEpochMs'], 1711267200000);
      expect(arguments['eventScheduledAtEpochMs'], 1711270800000);
      expect(arguments['reminderLeadTimeMinutes'], 60);
      return null;
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    await adapter.scheduleLocalNotification(
      NotificationJob(
        payload: const NotificationPayload(
          sourceType: NotificationSourceType.todo,
          sourceId: 'todo-1',
          petId: 'pet-1',
          routeTarget: NotificationRouteTarget.checklist,
        ),
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(1711267200000),
        eventScheduledAt: DateTime.fromMillisecondsSinceEpoch(1711270800000),
        reminderLeadTimeMinutes: 60,
        title: '补货主粮',
        body: 'Mochi · 低敏配方',
      ),
    );
  });

  test('has scheduled notification forwards key to native lookup', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'hasScheduledNotification');
      expect(call.arguments, 'todo:todo-1');
      return false;
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.hasScheduledNotification('todo:todo-1');

    expect(result, isFalse);
  });

  test('reset scheduled notifications forwards native request', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'resetScheduledNotifications');
      return null;
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    await expectLater(adapter.resetScheduledNotifications(), completes);
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

  test('open exact alarm settings returns unsupported when plugin is missing',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.openExactAlarmSettings();

    expect(result, NotificationSettingsOpenResult.unsupported);
  });

  test('get capabilities returns unsupported when plugin is missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });

    final adapter = MethodChannelNotificationPlatformAdapter(channel: channel);

    final result = await adapter.getCapabilities();

    expect(result.exactAlarmStatus, NotificationExactAlarmStatus.unsupported);
  });
}
