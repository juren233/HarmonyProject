import { AliRtcEngine, AliRtcVideoDimensions, AliRtcVideoEncoderConfiguration } from '@aliyun_video_cloud/alivcsdk_artc';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG = 'PetNoteRtcPlugin';
const CHANNEL_NAME = 'petnote/rtc';

export default class PetNoteRtcPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pluginBinding: FlutterPluginBinding | null = null;
  private engine: AliRtcEngine | null = null;
  private cameraEnabled: boolean = true;
  private microphoneEnabled: boolean = true;

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
    this.releaseEngine();
    this.pluginBinding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'initialize':
          this.ensureEngine();
          result.success(null);
          break;
        case 'join':
          this.join(call, result);
          break;
        case 'leave':
          this.engine?.leaveChannel();
          result.success(null);
          break;
        case 'toggleCamera':
          this.cameraEnabled = (call.argument('enabled') as boolean | undefined) !== false;
          this.engine?.publishLocalVideoStream(this.cameraEnabled);
          result.success(null);
          break;
        case 'toggleMicrophone':
          this.microphoneEnabled = (call.argument('enabled') as boolean | undefined) !== false;
          this.engine?.publishLocalAudioStream(this.microphoneEnabled);
          result.success(null);
          break;
        case 'toggleSpeaker':
          this.engine?.enableSpeakerphone((call.argument('enabled') as boolean | undefined) === true);
          result.success(null);
          break;
        case 'switchCamera':
          this.engine?.switchCamera();
          result.success(null);
          break;
        case 'dispose':
          this.releaseEngine();
          result.success(null);
          break;
        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      result.error('rtc_native_error', `${error}`, null);
    }
  }

  private ensureEngine(): AliRtcEngine {
    if (this.engine != null) {
      return this.engine;
    }
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      throw new Error('应用上下文不可用');
    }
    this.engine = AliRtcEngine.getInstance('', context);
    return this.engine;
  }

  private join(call: MethodCall, result: MethodResult): void {
    const engine = this.ensureEngine();
    const singleToken = this.requireString(call, 'singleToken');
    this.configureVideoEncoder(call, engine);
    const channelId = this.requireString(call, 'channelId');
    const userId = this.requireString(call, 'userId');
    engine.joinChannelWithToken(singleToken, channelId, userId, '');
    engine.publishLocalAudioStream(this.microphoneEnabled);
    engine.publishLocalVideoStream(this.cameraEnabled);
    result.success(null);
  }

  private requireString(call: MethodCall, key: string): string {
    const value = call.argument(key) as string | undefined;
    if (value == null || value.trim().length === 0) {
      throw new Error(`缺少 RTC 参数 ${key}`);
    }
    return value;
  }

  private configureVideoEncoder(call: MethodCall, engine: AliRtcEngine): void {
    const width = call.argument('videoWidth') as number | undefined;
    const height = call.argument('videoHeight') as number | undefined;
    if (width !== 1280 || height !== 720) {
      throw new Error('RTC 画质必须为 720P');
    }
    const config: AliRtcVideoEncoderConfiguration = new AliRtcVideoEncoderConfiguration();
    const dimensions: AliRtcVideoDimensions = new AliRtcVideoDimensions();
    dimensions.width = width;
    dimensions.height = height;
    config.dimensions = dimensions;
    engine.setVideoEncoderConfiguration(config);
  }

  private releaseEngine(): void {
    this.engine?.leaveChannel();
    AliRtcEngine.destroyInstance();
    this.engine = null;
  }
}
