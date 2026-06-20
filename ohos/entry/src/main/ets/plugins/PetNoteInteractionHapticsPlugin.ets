import vibrator from '@ohos.vibrator';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG = 'PetNoteInteractionHapticsPlugin';
const CHANNEL_NAME = 'petnote/interaction_haptics';
const DEFAULT_DELETE_HOLD_DURATION_MS = 560;

export default class PetNoteInteractionHapticsPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private playbackToken: number = 0;
  private timeoutIds: Array<number> = [];

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

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.stopDeleteHoldRamp();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'playDeleteHoldRamp':
        this.playDeleteHoldRamp(this.readDurationMs(call));
        result.success(null);
        break;
      case 'stopDeleteHoldRamp':
        this.stopDeleteHoldRamp();
        result.success(null);
        break;
      case 'playDeleteConfirmImpact':
        this.cancelScheduledRamp();
        this.playDeleteConfirmImpact();
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  private readDurationMs(call: MethodCall): number {
    const durationMs = call.argument('durationMs') as number | undefined;
    if (typeof durationMs === 'number' && durationMs >= 180) {
      return durationMs;
    }
    return DEFAULT_DELETE_HOLD_DURATION_MS;
  }

  private playDeleteHoldRamp(durationMs: number): void {
    this.stopDeleteHoldRamp();
    this.playbackToken += 1;
    const token = this.playbackToken;
    const step = Math.max(42, Math.floor(durationMs / 6));
    const durations: Array<number> = [12, 16, 20, 26, 32, 38];

    for (let index = 0; index < durations.length; index += 1) {
      const timeoutId = setTimeout(() => {
        if (token !== this.playbackToken) {
          return;
        }
        this.startTouchVibration(durations[index]);
      }, index * step);
      this.timeoutIds.push(timeoutId);
    }
  }

  private stopDeleteHoldRamp(): void {
    this.cancelScheduledRamp();
    vibrator.stopVibration(vibrator.VibratorStopMode.VIBRATOR_STOP_MODE_TIME).catch(() => {});
  }

  private cancelScheduledRamp(): void {
    this.playbackToken += 1;
    for (let index = 0; index < this.timeoutIds.length; index += 1) {
      clearTimeout(this.timeoutIds[index]);
    }
    this.timeoutIds = [];
  }

  private playDeleteConfirmImpact(): void {
    this.startTouchVibration(64);
  }

  private startTouchVibration(duration: number): void {
    vibrator.startVibration(
      { type: 'time', duration: duration },
      { id: 0, usage: 'touch' },
    ).catch(() => {});
  }
}
