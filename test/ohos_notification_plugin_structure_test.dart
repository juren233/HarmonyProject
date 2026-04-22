import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ohos project registrant wires the notification plugin into Flutter', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/ProjectPluginRegistrant.ets',
    ).readAsStringSync();

    expect(source, contains("import PetNoteNotificationPlugin from './PetNoteNotificationPlugin'"));
    expect(source, contains('flutterEngine.getPlugins()?.add(new PetNoteNotificationPlugin())'));
  });

  test('ohos notification plugin uses calendar kit reminder implementation', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteNotificationPlugin.ets',
    ).readAsStringSync();
    final moduleJson = File('ohos/entry/src/main/module.json5').readAsStringSync();

    expect(moduleJson, contains('ohos.permission.READ_CALENDAR'));
    expect(moduleJson, contains('ohos.permission.WRITE_CALENDAR'));
    expect(moduleJson, isNot(contains('ohos.permission.PUBLISH_AGENT_REMINDER')));
    expect(source, contains("import { calendarManager } from '@kit.CalendarKit';"));
    expect(source, contains('requestPermissionsFromUser(ability.context, permissions)'));
    expect(source, contains('requestPermissionOnSetting(ability.context, permissions)'));
    expect(source, contains('const grantStatuses = await atManager.requestPermissionOnSetting(ability.context, permissions);'));
    expect(source, contains('calendarManager.getCalendarManager(ability.context)'));
    expect(source, contains('const defaultCalendar = await manager.getCalendar();'));
    expect(source, contains('命中系统默认日历账户'));
    expect(source, contains('availableCalendars = await manager.getAllCalendars();'));
    expect(source, contains('const existingPetNoteCalendar = this.pickPetNoteCalendar(availableCalendars);'));
    expect(source, contains('命中宠记本地日历账户'));
    expect(source, contains('const localCalendar = await manager.getCalendar(this.petNoteCalendarAccount());'));
    expect(source, contains('const localCalendar = await manager.createCalendar(this.petNoteCalendarAccount());'));
    expect(source, contains('private pickPetNoteCalendar('));
    expect(source, contains('private petNoteCalendarAccount(): calendarManager.CalendarAccount'));
    expect(source, contains('private isPetNoteCalendarAccount(account: calendarManager.CalendarAccount): boolean'));
    expect(source, contains('private resolveEventStartTime(job: PetNoteNotificationJob): number'));
    expect(source, contains('private eventReminderOffsets(job: PetNoteNotificationJob): Array<number>'));
    expect(source, contains('const event: calendarManager.Event = {'));
    expect(source, contains('title: this.calendarTitle(job)'));
    expect(source, contains('description: this.calendarDescription()'));
    expect(source, contains("location: '请前往宠记App处理'"));
    expect(source, contains('isAllDay: false'));
    expect(source, contains('timeZone: this.currentTimeZone()'));
    expect(source, contains('const startTime = this.resolveEventStartTime(job);'));
    expect(source, contains('reminderTime: this.eventReminderOffsets(job)'));
    expect(source, contains('const eventId = await calendar.addEvent(event);'));
    expect(source, contains('await this.assertEventPersisted(calendar, eventId, identifier, startTime);'));
    expect(source, contains('await calendar.deleteEvent(eventId);'));
    expect(source, contains("case 'hasScheduledNotification':"));
    expect(source, contains('private async hasScheduledNotification(key: string): Promise<boolean>'));
    expect(source, contains('const eventId = await this.findEventIdByIdentifier(calendar, identifier);'));
    expect(source, contains('enableReminder: true'));
    expect(source, contains('const identifier = this.eventIdentifier(job.key);'));
    expect(source, contains('identifier: identifier'));
    expect(source, contains("await calendar.getEvents(undefined, ['id', 'identifier', 'startTime', 'timeZone', 'reminderTime'])"));
    expect(source, isNot(contains('calendar.queryEventInstances(')));
    expect(source, isNot(contains('回退到现有系统日历账户')));
    expect(source, isNot(contains('payloadDescription(')));
    expect(source, isNot(contains('reminderAgentManager.publishReminder(reminder)')));
    expect(source, isNot(contains('notificationManager.requestEnableNotification')));
    expect(source, isNot(contains("result.set('maxScheduledNotificationCount'")));
    expect(source, isNot(contains('workScheduler.startWork(work)')));
  });

  test('ohos notification permission request maps calendar authorization states', () {
    final source = File(
      'ohos/entry/src/main/ets/plugins/PetNoteNotificationPlugin.ets',
    ).readAsStringSync();

    expect(source, contains("const state = readGranted && writeGranted ? 'authorized' : 'denied';"));
    expect(source, contains('return state;'));
    expect(source, contains('日历权限尚未授权，准备在写入提醒前请求授权'));
    expect(source, contains('requestResult.dialogShownResults'));
    expect(source, contains('requestResult.errorReasons'));
    expect(source, contains('const promptHandled = this.didShowPermissionDialog(requestResult);'));
    expect(source, contains('const granted = authResults.length > 0 &&'));
    expect(source, contains('const afterState = await this.confirmCalendarPermissionState();'));
    expect(source, contains('this.hasHandledCalendarPermissionPrompt()'));
    expect(source, contains('getSelfPermissionStatus(PERMISSION_READ_CALENDAR)'));
    expect(source, contains('PermissionStatus.NOT_DETERMINED'));
    expect(source, contains("result.success('unknown')"));
    expect(source, contains('this.replyOpenNotificationSettings(result);'));
    expect(source, contains("result.success('opened')"));
    expect(source, contains("result.success('failed')"));
  });

  test('ohos custom notification plugin is explicitly version-controlled', () {
    final gitignore = File('.gitignore').readAsStringSync();

    expect(gitignore, contains('ohos/entry/src/main/ets/plugins/*'));
    expect(
      gitignore,
      contains('!ohos/entry/src/main/ets/plugins/PetNoteNotificationPlugin.ets'),
    );
  });

  test('ohos notification implementation removes legacy workscheduler fallback', () {
    final moduleJson = File('ohos/entry/src/main/module.json5').readAsStringSync();

    expect(moduleJson, isNot(contains('PetNoteNotificationWorkSchedulerExtensionAbility')));
    expect(moduleJson, isNot(contains('"type": "workScheduler"')));
    expect(
      File(
        'ohos/entry/src/main/ets/workscheduler/PetNoteNotificationWorkSchedulerExtensionAbility.ets',
      ).existsSync(),
      isFalse,
    );
  });
}
