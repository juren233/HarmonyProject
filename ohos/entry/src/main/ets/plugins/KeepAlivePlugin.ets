import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import window from '@ohos.window';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG = 'KeepAlivePlugin';
const CHANNEL_NAME = 'petnote/keep_alive';

export default class KeepAlivePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pluginBinding: FlutterPluginBinding | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
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
    this.pluginBinding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setKeepScreenOn':
        this.setKeepScreenOn(call, result);
        break;
      case 'startBackgroundKeepAlive':
        this.startBackgroundKeepAlive(result);
        break;
      case 'stopBackgroundKeepAlive':
        this.stopBackgroundKeepAlive(result);
        break;
      default:
        result.notImplemented();
    }
  }

  private setKeepScreenOn(call: MethodCall, result: MethodResult): void {
    const enabled = (call.argument('enabled') as boolean | undefined) === true;
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      result.error('keep_alive_unavailable', '应用上下文不可用', null);
      return;
    }
    window.getLastWindow(context)
      .then((mainWindow: window.Window) => {
        mainWindow.setWindowKeepScreenOn(enabled);
        result.success(null);
      })
      .catch(() => result.error('keep_alive_error', '设置屏幕常亮失败', null));
  }

  private startBackgroundKeepAlive(result: MethodResult): void {
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      result.error('keep_alive_unavailable', '应用上下文不可用', null);
      return;
    }
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.applicationInfo.name,
          abilityName: 'EntryAbility',
        },
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    wantAgent.getWantAgent(wantAgentInfo)
      .then((agent: WantAgent) => {
        backgroundTaskManager.startBackgroundRunning(
          context,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
          agent,
        );
        result.success(null);
      })
      .catch(() => result.error('keep_alive_error', '启动后台守护失败', null));
  }

  private stopBackgroundKeepAlive(result: MethodResult): void {
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      result.success(null);
      return;
    }
    try {
      backgroundTaskManager.stopBackgroundRunning(context);
      result.success(null);
    } catch (error) {
      result.success(null);
    }
  }
}
