import dataPreferences from '@ohos.data.preferences';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG = 'PetNoteAiSecretStorePlugin';
const CHANNEL_NAME = 'petnote/ai_secret_store';
const PREFERENCES_FILE_NAME = 'petnote_ai_secret_store';

export default class PetNoteAiSecretStorePlugin
  implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private preferences: dataPreferences.Preferences | null = null;
  private available: boolean = false;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    try {
      this.preferences = dataPreferences.getPreferencesSync(
        binding.getApplicationContext(),
        { name: PREFERENCES_FILE_NAME },
      );
      this.available = true;
    } catch (error) {
      this.available = false;
      this.preferences = null;
    }
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
    this.available = false;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'isAvailable':
          result.success(this.available);
          break;
        case 'readKey':
          this.handleReadKey(call, result);
          break;
        case 'hasKeys':
          this.handleHasKeys(call, result);
          break;
        case 'writeKey':
          this.handleWriteKey(call, result);
          break;
        case 'deleteKey':
          this.handleDeleteKey(call, result);
          break;
        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      result.error('ai_secret_store_error', this.describeError(error), null);
    }
  }

  private handleReadKey(call: MethodCall, result: MethodResult): void {
    const configId: Object | null = call.argument('configId');
    if (typeof configId !== 'string' || configId.length === 0) {
      result.success(null);
      return;
    }
    const prefs = this.requirePreferences();
    if (!prefs.hasSync(configId)) {
      result.success(null);
      return;
    }
    const value = prefs.getSync(configId, '') as string;
    result.success(value.length > 0 ? value : null);
  }

  private handleHasKeys(call: MethodCall, result: MethodResult): void {
    const rawConfigIds: Object | null = call.argument('configIds');
    if (!Array.isArray(rawConfigIds)) {
      result.success({});
      return;
    }
    const prefs = this.requirePreferences();
    const states: Record<string, boolean> = {};
    rawConfigIds.forEach((item: Object) => {
      if (typeof item === 'string') {
        const configId = item as string;
        if (prefs.hasSync(configId)) {
          const value = prefs.getSync(configId, '') as string;
          states[configId] = value.length > 0;
        } else {
          states[configId] = false;
        }
      }
    });
    result.success(states);
  }

  private handleWriteKey(call: MethodCall, result: MethodResult): void {
    const configId: Object | null = call.argument('configId');
    const value: Object | null = call.argument('value');
    if (typeof configId !== 'string' || configId.length === 0) {
      result.success(null);
      return;
    }
    if (value == null || typeof value !== 'string') {
      result.success(null);
      return;
    }
    const prefs = this.requirePreferences();
    prefs.putSync(configId, value as string);
    prefs.flushSync();
    result.success(null);
  }

  private handleDeleteKey(call: MethodCall, result: MethodResult): void {
    const configId: Object | null = call.argument('configId');
    if (typeof configId !== 'string' || configId.length === 0) {
      result.success(null);
      return;
    }
    const prefs = this.requirePreferences();
    if (prefs.hasSync(configId)) {
      prefs.deleteSync(configId);
      prefs.flushSync();
    }
    result.success(null);
  }

  private requirePreferences(): dataPreferences.Preferences {
    if (this.preferences == null) {
      throw new Error('AI secret store preferences not available');
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
