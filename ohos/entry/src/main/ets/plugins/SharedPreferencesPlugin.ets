import dataPreferences from '@ohos.data.preferences';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'SharedPreferencesPlugin';
const CHANNEL_NAME = 'plugins.flutter.io/shared_preferences';
const PREFERENCES_FILE_NAME = 'FlutterSharedPreferences';
const DEFAULT_PREFIX = 'flutter.';

interface SharedPreferencesFilter {
  prefix: string;
  allowList: Array<string> | null;
}

type SharedPreferencesValue = dataPreferences.ValueType;
type SharedPreferencesMap = Record<string, SharedPreferencesValue>;

export default class SharedPreferencesPlugin
  implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private preferences: dataPreferences.Preferences | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.preferences = dataPreferences.getPreferencesSync(
      binding.getApplicationContext(),
      { name: PREFERENCES_FILE_NAME },
    );
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
    this.preferences = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'getAll':
          result.success(this.readAllWithFilter(this.defaultFilter()));
          break;
        case 'getAllWithParameters':
          result.success(this.readAllWithFilter(this.readFilter(call)));
          break;
        case 'setBool':
          this.writeValue(call, this.readBoolArg(call, 'value'));
          result.success(true);
          break;
        case 'setInt':
          this.writeValue(call, this.readNumberArg(call, 'value', true));
          result.success(true);
          break;
        case 'setDouble':
          this.writeValue(call, this.readNumberArg(call, 'value', false));
          result.success(true);
          break;
        case 'setString':
          this.writeValue(call, this.readStringArg(call, 'value'));
          result.success(true);
          break;
        case 'setStringList':
          this.writeValue(call, this.readStringListArg(call, 'value'));
          result.success(true);
          break;
        case 'remove':
          this.deleteKey(this.readStringArg(call, 'key'));
          result.success(true);
          break;
        case 'clear':
          this.clearWithFilter(this.defaultFilter());
          result.success(true);
          break;
        case 'clearWithParameters':
          this.clearWithFilter(this.readFilter(call));
          result.success(true);
          break;
        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      Log.e(TAG, '处理共享偏好调用失败：' + this.describeError(error));
      result.error('shared_preferences_error', '共享偏好处理失败', null);
    }
  }

  private defaultFilter(): SharedPreferencesFilter {
    return {
      prefix: DEFAULT_PREFIX,
      allowList: null,
    };
  }

  private readFilter(call: MethodCall): SharedPreferencesFilter {
    const rawPrefix: Object | null = call.argument('prefix');
    const rawAllowList: Object | null = call.argument('allowList');
    return {
      prefix: typeof rawPrefix === 'string' ? rawPrefix : DEFAULT_PREFIX,
      allowList: this.normalizeAllowList(rawAllowList),
    };
  }

  private readAllWithFilter(filter: SharedPreferencesFilter): SharedPreferencesMap {
    const allValues = this.readAllSync();
    const filteredValues: SharedPreferencesMap = {};
    Object.keys(allValues).forEach((key: string) => {
      if (this.matchesFilter(key, filter)) {
        filteredValues[key] = allValues[key];
      }
    });
    return filteredValues;
  }

  private clearWithFilter(filter: SharedPreferencesFilter): void {
    const keysToDelete = Object.keys(this.readAllSync()).filter(
      (key: string) => this.matchesFilter(key, filter),
    );
    if (keysToDelete.length === 0) {
      return;
    }
    const preferences = this.requirePreferences();
    keysToDelete.forEach((key: string) => {
      preferences.deleteSync(key);
    });
    preferences.flushSync();
  }

  private writeValue(call: MethodCall, value: SharedPreferencesValue): void {
    const key = this.readStringArg(call, 'key');
    const preferences = this.requirePreferences();
    preferences.putSync(key, value);
    preferences.flushSync();
  }

  private deleteKey(key: string): void {
    const preferences = this.requirePreferences();
    preferences.deleteSync(key);
    preferences.flushSync();
  }

  private readAllSync(): SharedPreferencesMap {
    const rawValues = this.requirePreferences().getAllSync() as SharedPreferencesMap;
    const normalizedValues: SharedPreferencesMap = {};
    Object.keys(rawValues).forEach((key: string) => {
      normalizedValues[key] = rawValues[key];
    });
    return normalizedValues;
  }

  private matchesFilter(key: string, filter: SharedPreferencesFilter): boolean {
    if (!key.startsWith(filter.prefix)) {
      return false;
    }
    const allowList = filter.allowList;
    return allowList == null || allowList.includes(key);
  }

  private normalizeAllowList(value: Object | null): Array<string> | null {
    if (!Array.isArray(value)) {
      return null;
    }
    const allowList: Array<string> = [];
    value.forEach((item: Object) => {
      if (typeof item === 'string') {
        allowList.push(item);
      }
    });
    return allowList;
  }

  private readStringArg(call: MethodCall, key: string): string {
    const value: Object | null = call.argument(key);
    if (typeof value !== 'string') {
      throw new Error(`参数 ${key} 不是字符串`);
    }
    return value;
  }

  private readBoolArg(call: MethodCall, key: string): boolean {
    const value: Object | null = call.argument(key);
    if (typeof value !== 'boolean') {
      throw new Error(`参数 ${key} 不是布尔值`);
    }
    return value;
  }

  private readNumberArg(
    call: MethodCall,
    key: string,
    expectInteger: boolean,
  ): number {
    const value: Object | null = call.argument(key);
    if (typeof value !== 'number') {
      throw new Error(`参数 ${key} 不是数字`);
    }
    if (expectInteger && !Number.isInteger(value)) {
      throw new Error(`参数 ${key} 不是整数`);
    }
    return value;
  }

  private readStringListArg(call: MethodCall, key: string): Array<string> {
    const value: Object | null = call.argument(key);
    if (!Array.isArray(value)) {
      throw new Error(`参数 ${key} 不是字符串数组`);
    }
    const results: Array<string> = [];
    value.forEach((item: Object) => {
      if (typeof item !== 'string') {
        throw new Error(`参数 ${key} 包含非字符串元素`);
      }
      results.push(item);
    });
    return results;
  }

  private requirePreferences(): dataPreferences.Preferences {
    if (this.preferences == null) {
      throw new Error('共享偏好实例不可用');
    }
    return this.preferences;
  }

  private describeError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
