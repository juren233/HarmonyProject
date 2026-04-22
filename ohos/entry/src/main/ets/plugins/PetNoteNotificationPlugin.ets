import { abilityAccessCtrl, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { calendarManager } from '@kit.CalendarKit';
import bundleManager from '@ohos.bundle.bundleManager';
import Want from '@ohos.app.ability.Want';
import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding, NewWantListener } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'PetNoteNotificationPlugin';
const CHANNEL_NAME = 'petnote/notifications';
const CALENDAR_ACCOUNT_NAME = 'petnote_local_reminders';
const CALENDAR_ACCOUNT_DISPLAY_NAME = '宠记提醒';
const CALENDAR_PERMISSION_GRANTED = 0;
const PERMISSION_READ_CALENDAR: Permissions = 'ohos.permission.READ_CALENDAR';
const PERMISSION_WRITE_CALENDAR: Permissions = 'ohos.permission.WRITE_CALENDAR';
const PARAM_SOURCE_TYPE = 'petnote_source_type';
const PARAM_SOURCE_ID = 'petnote_source_id';
const PARAM_PET_ID = 'petnote_pet_id';
const PARAM_ROUTE_TARGET = 'petnote_route_target';

interface PetNotePayload {
  sourceType: string;
  sourceId: string;
  petId: string;
  routeTarget: string;
}

interface PetNoteNotificationJob {
  key: string;
  scheduledAtEpochMs: number;
  eventScheduledAtEpochMs: number;
  reminderLeadTimeMinutes: number;
  title: string;
  body: string;
  payload: PetNotePayload;
}

interface PetNoteLaunchIntent {
  payload: PetNotePayload;
  fromForeground: boolean;
}

interface PetNoteCapabilitiesResult {
  exactAlarmStatus: string;
}

interface PetNotePermissionRequestResult {
  state: string;
  promptHandled: boolean;
}

export default class PetNoteNotificationPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware, NewWantListener {
  private channel: MethodChannel | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private ability: UIAbility | null = null;
  private initialLaunchIntent: PetNoteLaunchIntent | null = null;
  private pendingForegroundTap: PetNoteLaunchIntent | null = null;
  private calendarMgr: calendarManager.CalendarManager | null = null;
  private calendar: calendarManager.Calendar | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
      StandardMethodCodec.INSTANCE,
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    this.ability = binding.getAbility();
    binding.addOnNewWantListener(this);
    this.initialLaunchIntent = this.extractLaunchIntent(this.ability.launchWant, false);
  }

  onDetachedFromAbility(): void {
    this.abilityBinding?.removeOnNewWantListener(this);
    this.abilityBinding = null;
    this.ability = null;
    this.calendarMgr = null;
    this.calendar = null;
  }

  onNewWant(want: Want, _launchParams: AbilityConstant.LaunchParam): void {
    const launchIntent = this.extractLaunchIntent(want, true);
    if (launchIntent != null) {
      this.pendingForegroundTap = launchIntent;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, '收到通知通道调用 method=' + call.method);
    switch (call.method) {
      case 'initialize':
        result.success(null);
        break;
      case 'getPermissionState':
        this.replyPermissionState(result);
        break;
      case 'hasHandledPermissionPrompt':
        this.replyPermissionPromptHandled(result);
        break;
      case 'requestPermission':
        this.replyRequestPermission(result);
        break;
      case 'scheduleLocalNotification':
        this.replyScheduleLocalNotification(call, result);
        break;
      case 'hasScheduledNotification':
        this.replyHasScheduledNotification(call, result);
        break;
      case 'cancelNotification':
        this.replyCancelNotification(call, result);
        break;
      case 'resetScheduledNotifications':
        this.replyResetScheduledNotifications(result);
        break;
      case 'getInitialLaunchIntent':
        result.success(this.consumeInitialLaunchIntent());
        break;
      case 'consumeForegroundTap':
        result.success(this.consumeForegroundTap());
        break;
      case 'registerPushToken':
        result.success(null);
        break;
      case 'openNotificationSettings':
        this.replyOpenNotificationSettings(result);
        break;
      case 'getCapabilities':
        result.success(this.capabilitiesToMap());
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private replyPermissionState(result: MethodResult): void {
    this.calendarPermissionState()
      .then((state: string) => {
        result.success(state);
      })
      .catch((error: BusinessError) => {
        Log.e(TAG, '读取日历权限失败：' + this.describeError(error));
        result.success('unknown');
      });
  }


  private replyPermissionPromptHandled(result: MethodResult): void {
    try {
      result.success(this.hasHandledCalendarPermissionPrompt());
    } catch (error) {
      Log.e(TAG, '读取日历权限弹窗操作状态失败：' + this.describeError(error));
      result.success(false);
    }
  }

  private replyOpenNotificationSettings(result: MethodResult): void {
    const ability = this.ability;
    if (ability == null) {
      result.success('unsupported');
      return;
    }
    this.openCalendarPermissionSettings(ability)
      .then(() => {
        result.success('opened');
      })
      .catch((error: BusinessError) => {
        Log.e(TAG, '打开日历权限设置失败：' + this.describeError(error));
        result.success('failed');
      });
  }

  private replyRequestPermission(result: MethodResult): void {
    const ability = this.ability;
    if (ability == null) {
      result.success({ state: 'unsupported', promptHandled: false });
      return;
    }
    this.requestCalendarPermissions(ability)
      .then((requestResult: PetNotePermissionRequestResult) => {
        result.success(requestResult);
      })
      .catch((error: BusinessError) => {
        Log.e(TAG, '请求日历权限失败：' + this.describeError(error));
        result.success({ state: 'unknown', promptHandled: false });
      });
  }

  private replyScheduleLocalNotification(call: MethodCall, result: MethodResult): void {
    const job = this.parseNotificationJob(call);
    if (job == null) {
      Log.e(TAG, '通知任务参数无效 args=' + this.describeValue(call.args));
      result.error('invalid_notification_job', '通知任务参数无效', null);
      return;
    }
    this.scheduleLocalNotification(job)
      .then(() => {
        result.success(null);
      })
      .catch((error: Error) => {
        Log.e(TAG, '调度本地通知失败：' + this.describeError(error));
        result.error('schedule_notification_failed', '调度本地通知失败', null);
      });
  }

  private replyHasScheduledNotification(call: MethodCall, result: MethodResult): void {
    const key = call.args as string;
    if (key == null || key.length === 0) {
      result.success(false);
      return;
    }
    this.hasScheduledNotification(key)
      .then((exists: boolean) => {
        result.success(exists);
      })
      .catch((error: Error) => {
        Log.e(TAG, '回查本地通知失败：' + this.describeError(error));
        result.success(false);
      });
  }

  private replyCancelNotification(call: MethodCall, result: MethodResult): void {
    const key = call.args as string;
    if (key == null || key.length === 0) {
      result.success(null);
      return;
    }
    this.cancelNotification(key)
      .then(() => {
        result.success(null);
      })
      .catch((error: Error) => {
        Log.e(TAG, '取消本地通知失败：' + this.describeError(error));
        result.error('cancel_notification_failed', '取消本地通知失败', null);
      });
  }

  private replyResetScheduledNotifications(result: MethodResult): void {
    this.resetScheduledNotifications()
      .then(() => {
        result.success(null);
      })
      .catch((error: Error) => {
        Log.e(TAG, '重置本地通知失败：' + this.describeError(error));
        result.error('reset_notification_failed', '重置本地通知失败', null);
      });
  }

  private async calendarPermissionState(): Promise<string> {
    const ability = this.ability;
    if (ability == null) {
      return 'unsupported';
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = this.accessTokenId();
    const readGranted = atManager.checkAccessTokenSync(tokenId, PERMISSION_READ_CALENDAR) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    const writeGranted = atManager.checkAccessTokenSync(tokenId, PERMISSION_WRITE_CALENDAR) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    const state = readGranted && writeGranted ? 'authorized' : 'denied';
    Log.i(TAG, '当前日历权限状态 state=' + state + ', readGranted=' + readGranted + ', writeGranted=' + writeGranted);
    return state;
  }

  private hasHandledCalendarPermissionPrompt(): boolean {
    const ability = this.ability;
    if (ability == null) {
      return false;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const statuses = [
      atManager.getSelfPermissionStatus(PERMISSION_READ_CALENDAR),
      atManager.getSelfPermissionStatus(PERMISSION_WRITE_CALENDAR),
    ];
    return statuses.some((status: abilityAccessCtrl.PermissionStatus) => {
      return status !== abilityAccessCtrl.PermissionStatus.NOT_DETERMINED &&
        status !== abilityAccessCtrl.PermissionStatus.INVALID;
    });
  }

  private async openCalendarPermissionSettings(ability: UIAbility): Promise<void> {
    const permissions: Array<Permissions> = [PERMISSION_READ_CALENDAR, PERMISSION_WRITE_CALENDAR];
    const atManager = abilityAccessCtrl.createAtManager();
    const grantStatuses = await atManager.requestPermissionOnSetting(ability.context, permissions);
    Log.i(TAG, '日历权限设置页返回 grantStatuses=' + JSON.stringify(grantStatuses));
    this.calendar = null;
    this.calendarMgr = null;
  }

  private async requestCalendarPermissions(ability: UIAbility): Promise<PetNotePermissionRequestResult> {
    const permissions: Array<Permissions> = [PERMISSION_READ_CALENDAR, PERMISSION_WRITE_CALENDAR];
    const beforeState = await this.calendarPermissionState();
    const atManager = abilityAccessCtrl.createAtManager();
    const requestResult = await atManager.requestPermissionsFromUser(ability.context, permissions) as PermissionRequestResult;
    const authResults = requestResult.authResults ?? [];
    const dialogShownResults = requestResult.dialogShownResults ?? [];
    const errorReasons = requestResult.errorReasons ?? [];
    const granted = authResults.length > 0 &&
      authResults.every((item: number) => item === CALENDAR_PERMISSION_GRANTED);
    this.calendar = null;
    this.calendarMgr = null;
    const afterState = await this.confirmCalendarPermissionState();
    const promptHandled = this.didShowPermissionDialog(requestResult);
    const state = afterState === 'authorized' || granted ? 'authorized' : 'denied';
    Log.i(TAG, '日历权限请求完成 beforeState=' + beforeState +
      ', afterState=' + afterState +
      ', granted=' + granted +
      ', promptHandled=' + promptHandled +
      ', permissions=' + JSON.stringify(requestResult.permissions ?? []) +
      ', authResults=' + JSON.stringify(authResults) +
      ', dialogShownResults=' + JSON.stringify(dialogShownResults) +
      ', errorReasons=' + JSON.stringify(errorReasons));
    return {
      state: state,
      promptHandled: promptHandled,
    };
  }

  private didShowPermissionDialog(requestResult: PermissionRequestResult): boolean {
    const dialogShownResults = requestResult.dialogShownResults ?? [];
    return dialogShownResults.some((item: boolean) => item);
  }

  private async scheduleLocalNotification(job: PetNoteNotificationJob): Promise<void> {
    Log.i(TAG, '开始写入系统日历提醒 key=' + job.key + ', scheduledAtEpochMs=' + job.scheduledAtEpochMs +
      ', eventScheduledAtEpochMs=' + job.eventScheduledAtEpochMs + ', reminderLeadTimeMinutes=' + job.reminderLeadTimeMinutes);
    const calendar = await this.ensureCalendarReady();
    await this.cancelNotification(job.key);
    const startTime = this.resolveEventStartTime(job);
    const identifier = this.eventIdentifier(job.key);
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: this.calendarTitle(job),
      description: this.calendarDescription(),
      location: {
        location: '请前往宠记App处理',
      },
      startTime: startTime,
      endTime: startTime + 5 * 60 * 1000,
      isAllDay: false,
      timeZone: this.currentTimeZone(),
      reminderTime: this.eventReminderOffsets(job),
      identifier: identifier,
    };
    const eventId = await calendar.addEvent(event);
    await this.assertEventPersisted(calendar, eventId, identifier, startTime);
    Log.i(TAG, '写入系统日历提醒成功 key=' + job.key + ', eventId=' + eventId + ', startTime=' + startTime);
  }

  private async cancelNotification(key: string): Promise<void> {
    const calendar = await this.ensureCalendarReady();
    const identifier = this.eventIdentifier(key);
    const eventId = await this.findEventIdByIdentifier(calendar, identifier);
    if (eventId == null) {
      Log.i(TAG, '未查询到需要删除的日历提醒 identifier=' + identifier);
      return;
    }
    await calendar.deleteEvent(eventId);
    Log.i(TAG, '删除系统日历提醒成功 identifier=' + identifier + ', eventId=' + eventId);
  }

  private async hasScheduledNotification(key: string): Promise<boolean> {
    const calendar = await this.ensureCalendarReady();
    const identifier = this.eventIdentifier(key);
    const eventId = await this.findEventIdByIdentifier(calendar, identifier);
    const exists = eventId != null;
    Log.i(TAG, '回查系统日历提醒 identifier=' + identifier + ', exists=' + exists +
      (eventId == null ? '' : ', eventId=' + eventId));
    return exists;
  }

  private async resetScheduledNotifications(): Promise<void> {
    const calendar = await this.ensureCalendarReady();
    const events = await calendar.getEvents();
    for (let index = 0; index < events.length; index += 1) {
      const event = events[index];
      if (typeof event.identifier !== 'string' || !event.identifier.startsWith('petnote:')) {
        continue;
      }
      if (typeof event.id !== 'number' || event.id <= 0) {
        continue;
      }
      await calendar.deleteEvent(event.id);
      Log.i(TAG, '已删除历史宠记日历提醒 identifier=' + event.identifier + ', eventId=' + event.id);
    }
  }

  private async ensureCalendarReady(): Promise<calendarManager.Calendar> {
    const ability = this.ability;
    if (ability == null) {
      throw new Error('当前 Ability 不可用，无法创建日历提醒');
    }
    const permissionState = await this.calendarPermissionState();
    if (permissionState !== 'authorized') {
      Log.i(TAG, '日历权限尚未授权，准备在写入提醒前请求授权 state=' + permissionState);
      const requestedResult = await this.requestCalendarPermissions(ability);
      if (requestedResult.state !== 'authorized') {
        throw new Error('当前未授予日历读写权限，无法创建系统日历提醒，state=' + requestedResult.state);
      }
    }
    if (this.calendar != null) {
      return this.calendar;
    }
    const manager = this.calendarMgr ?? calendarManager.getCalendarManager(ability.context);
    this.calendarMgr = manager;
    this.calendar = await this.resolveWritableCalendar(manager);
    await this.calendar.setConfig({
      enableReminder: true,
    });
    const activeAccount = this.calendar.getAccount();
    Log.i(TAG, '当前写入日历提醒账户已启用提醒 name=' + activeAccount.name +
      ', displayName=' + (activeAccount.displayName ?? '') +
      ', type=' + activeAccount.type);
    return this.calendar as calendarManager.Calendar;
  }

  private async resolveWritableCalendar(
    manager: calendarManager.CalendarManager,
  ): Promise<calendarManager.Calendar> {
    try {
      const defaultCalendar = await manager.getCalendar();
      const defaultAccount = defaultCalendar.getAccount();
      Log.i(TAG, '命中系统默认日历账户 name=' + defaultAccount.name +
        ', displayName=' + (defaultAccount.displayName ?? '') +
        ', type=' + defaultAccount.type);
      return defaultCalendar;
    } catch (error) {
      Log.i(TAG, '读取系统默认日历账户失败，准备回退宠记本地日历。error=' + this.describeError(error));
    }

    let availableCalendars: Array<calendarManager.Calendar> = [];
    try {
      availableCalendars = await manager.getAllCalendars();
      Log.i(TAG, '当前系统日历账户列表=' + this.describeCalendars(availableCalendars));
    } catch (error) {
      Log.i(TAG, '读取系统日历账户列表失败，继续尝试宠记本地日历。error=' + this.describeError(error));
    }

    const existingPetNoteCalendar = this.pickPetNoteCalendar(availableCalendars);
    if (existingPetNoteCalendar != null) {
      const existingAccount = existingPetNoteCalendar.getAccount();
      Log.i(TAG, '命中宠记本地日历账户 name=' + existingAccount.name +
        ', displayName=' + (existingAccount.displayName ?? '') +
        ', type=' + existingAccount.type);
      return existingPetNoteCalendar;
    }

    try {
      const localCalendar = await manager.getCalendar(this.petNoteCalendarAccount());
      Log.i(TAG, '宠记本地日历账户已存在 name=' + CALENDAR_ACCOUNT_NAME);
      return localCalendar;
    } catch (error) {
      Log.i(TAG, '宠记本地日历账户不存在，准备创建。error=' + this.describeError(error));
    }

    const localCalendar = await manager.createCalendar(this.petNoteCalendarAccount());
    Log.i(TAG, '宠记本地日历账户创建成功 name=' + CALENDAR_ACCOUNT_NAME);
    return localCalendar;
  }

  private async confirmCalendarPermissionState(): Promise<string> {
    let state = await this.calendarPermissionState();
    if (state === 'authorized') {
      return state;
    }
    await this.sleep(220);
    state = await this.calendarPermissionState();
    if (state === 'authorized') {
      return state;
    }
    await this.sleep(380);
    return this.calendarPermissionState();
  }

  private pickPetNoteCalendar(
    calendars: Array<calendarManager.Calendar>,
  ): calendarManager.Calendar | null {
    for (let index = 0; index < calendars.length; index += 1) {
      const calendar = calendars[index];
      const account = calendar.getAccount();
      if (this.isPetNoteCalendarAccount(account)) {
        return calendar;
      }
    }
    return null;
  }

  private petNoteCalendarAccount(): calendarManager.CalendarAccount {
    return {
      name: CALENDAR_ACCOUNT_NAME,
      type: calendarManager.CalendarType.LOCAL,
      displayName: CALENDAR_ACCOUNT_DISPLAY_NAME,
    };
  }

  private isPetNoteCalendarAccount(account: calendarManager.CalendarAccount): boolean {
    return account.type === calendarManager.CalendarType.LOCAL &&
      account.name === CALENDAR_ACCOUNT_NAME;
  }

  private async findEventIdByIdentifier(calendar: calendarManager.Calendar, identifier: string): Promise<number | null> {
    const events = await calendar.getEvents();
    for (let index = 0; index < events.length; index += 1) {
      const event = events[index];
      if (event.identifier !== identifier) {
        continue;
      }
      if (typeof event.id === 'number' && event.id > 0) {
        return event.id;
      }
    }
    return null;
  }

  private resolveEventStartTime(job: PetNoteNotificationJob): number {
    const candidate = job.eventScheduledAtEpochMs > 0 ? job.eventScheduledAtEpochMs : job.scheduledAtEpochMs;
    const now = Date.now();
    return candidate > now ? candidate : now + 60 * 1000;
  }

  private eventReminderOffsets(job: PetNoteNotificationJob): Array<number> {
    const leadTimeMinutes = job.reminderLeadTimeMinutes;
    if (leadTimeMinutes > 0) {
      return [leadTimeMinutes];
    }
    return [0];
  }

  private async assertEventPersisted(
    calendar: calendarManager.Calendar,
    eventId: number,
    identifier: string,
    startTime: number,
  ): Promise<void> {
    const events = await calendar.getEvents(undefined, ['id', 'identifier', 'startTime', 'timeZone', 'reminderTime']);
    for (let index = 0; index < events.length; index += 1) {
      const event = events[index];
      if (event.id === eventId || event.identifier === identifier) {
        Log.i(TAG, '日历事件回查成功 eventId=' + eventId + ', identifier=' + identifier +
          ', eventStartTime=' + event.startTime + ', timeZone=' + (event.timeZone ?? ''));
        return;
      }
    }

    throw new Error('CalendarKit 写入后未查询到事件 eventId=' + eventId + ', identifier=' + identifier);
  }

  private calendarTitle(job: PetNoteNotificationJob): string {
    const petName = this.jobPetName(job.body);
    const title = this.normalizeCalendarText(job.title, '宠记提醒');
    const supplementalNote = this.jobSupplementalNote(job.body);
    return [petName, title, supplementalNote]
      .filter((part: string) => part.length > 0)
      .join(' · ');
  }

  private calendarDescription(): string {
    return '';
  }

  private jobPetName(body: string): string {
    const parts = body.split(' · ');
    return this.normalizeCalendarText(parts.length > 0 ? parts[0] : '', '爱宠');
  }

  private jobSupplementalNote(body: string): string {
    const parts = body
      .split(' · ')
      .map((part: string) => part.trim())
      .filter((part: string) => part.length > 0);
    if (parts.length <= 1) {
      return '';
    }
    return parts.slice(1).join(' · ');
  }

  private normalizeCalendarText(value: string, fallback: string): string {
    const trimmed = value.trim();
    return trimmed.length === 0 ? fallback : trimmed;
  }

  private eventIdentifier(key: string): string {
    return 'petnote:' + key;
  }

  private currentTimeZone(): string | undefined {
    try {
      const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      return typeof timeZone === 'string' && timeZone.length > 0 ? timeZone : undefined;
    } catch (error) {
      Log.i(TAG, '读取当前时区失败，继续使用系统默认时区。error=' + this.describeError(error));
      return undefined;
    }
  }

  private describeCalendars(calendars: Array<calendarManager.Calendar>): string {
    if (calendars.length === 0) {
      return '[]';
    }
    const descriptions: Array<string> = [];
    for (let index = 0; index < calendars.length; index += 1) {
      const account = calendars[index].getAccount();
      descriptions.push(JSON.stringify({
        name: account.name,
        displayName: account.displayName ?? '',
        type: account.type,
      }));
    }
    return descriptions.join(' | ');
  }

  private async sleep(durationMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), durationMs);
    });
  }

  private parseNotificationJob(call: MethodCall): PetNoteNotificationJob | null {
    const payload = this.parsePayload(call.argument('payload'));
    if (payload == null) {
      return null;
    }
    return {
      key: this.readStringValue(call.argument('key')),
      scheduledAtEpochMs: this.readNumberValue(call.argument('scheduledAtEpochMs')),
      eventScheduledAtEpochMs: this.readNumberValue(call.argument('eventScheduledAtEpochMs')),
      reminderLeadTimeMinutes: this.readNumberValue(call.argument('reminderLeadTimeMinutes')),
      title: this.readStringValue(call.argument('title')),
      body: this.readStringValue(call.argument('body')),
      payload: payload,
    };
  }

  private parsePayload(args: Any): PetNotePayload | null {
    if (args == null) {
      return null;
    }
    return {
      sourceType: this.readString(args, 'sourceType'),
      sourceId: this.readString(args, 'sourceId'),
      petId: this.readString(args, 'petId'),
      routeTarget: this.readString(args, 'routeTarget'),
    };
  }

  private extractLaunchIntent(want: Want | null, fromForeground: boolean): PetNoteLaunchIntent | null {
    const parameters = want?.parameters;
    if (parameters == null) {
      return null;
    }
    const sourceType = this.readString(parameters, PARAM_SOURCE_TYPE);
    const sourceId = this.readString(parameters, PARAM_SOURCE_ID);
    if (sourceType.length === 0 || sourceId.length === 0) {
      return null;
    }
    return {
      payload: {
        sourceType: sourceType,
        sourceId: sourceId,
        petId: this.readString(parameters, PARAM_PET_ID),
        routeTarget: this.readString(parameters, PARAM_ROUTE_TARGET),
      },
      fromForeground: fromForeground,
    };
  }

  private consumeInitialLaunchIntent(): Map<string, Object> | null {
    const launchIntent = this.initialLaunchIntent;
    this.initialLaunchIntent = null;
    return this.launchIntentToMap(launchIntent);
  }

  private consumeForegroundTap(): Map<string, Object> | null {
    const launchIntent = this.pendingForegroundTap;
    this.pendingForegroundTap = null;
    return this.launchIntentToMap(launchIntent);
  }

  private launchIntentToMap(launchIntent: PetNoteLaunchIntent | null): Map<string, Object> | null {
    if (launchIntent == null) {
      return null;
    }
    const result: Map<string, Object> = new Map<string, Object>();
    result.set('payload', this.payloadToMap(launchIntent.payload));
    result.set('fromForeground', launchIntent.fromForeground);
    return result;
  }

  private payloadToMap(payload: PetNotePayload): Map<string, Object> {
    const result: Map<string, Object> = new Map<string, Object>();
    result.set('sourceType', payload.sourceType);
    result.set('sourceId', payload.sourceId);
    result.set('petId', payload.petId);
    result.set('routeTarget', payload.routeTarget);
    return result;
  }

  private capabilitiesToMap(): Map<string, Object> {
    const capabilities: PetNoteCapabilitiesResult = {
      exactAlarmStatus: 'unsupported',
    };
    const result: Map<string, Object> = new Map<string, Object>();
    result.set('exactAlarmStatus', capabilities.exactAlarmStatus);
    return result;
  }

  private accessTokenId(): number {
    return bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
    ).appInfo.accessTokenId;
  }

  private readString(args: Any, key: string): string {
    if (args instanceof Map) {
      return this.readStringValue((args as Map<string, Object>).get(key));
    }
    const record = args as Record<string, Object>;
    return this.readStringValue(record[key]);
  }

  private readStringValue(value: Any): string {
    return typeof value === 'string' ? value : '';
  }

  private readNumberValue(value: Any): number {
    return typeof value === 'number' ? value : 0;
  }

  private describeError(error: Object): string {
    const businessError = error as BusinessError;
    return JSON.stringify({
      code: businessError?.code,
      message: businessError?.message,
      name: businessError?.name,
    });
  }

  private describeValue(value: Any): string {
    try {
      return JSON.stringify(value);
    } catch (error) {
      return String(value);
    }
  }
}
