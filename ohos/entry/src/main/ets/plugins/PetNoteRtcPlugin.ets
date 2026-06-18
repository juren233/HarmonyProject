import { abilityAccessCtrl, bundleManager, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import UIAbility from '@ohos.app.ability.UIAbility';
import { AliRtcAudioTrack, AliRtcChannelProfile, AliRtcClientRole, AliRtcEngine, AliRtcEngineEventListener, AliRtcRenderMode, AliRtcVideoCanvas, AliRtcVideoDimensions, AliRtcVideoEncoderConfiguration, AliRtcVideoTrack, AliRtcXComponentController } from '@aliyun_video_cloud/alivcsdk_artc';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';

const TAG = 'PetNoteRtcPlugin';
const CHANNEL_NAME = 'petnote/rtc';
const VIDEO_VIEW_TYPE = 'petnote/rtc_video_view';
const MEDIA_PERMISSION_GRANTED = 0;
const PERMISSION_CAMERA: Permissions = 'ohos.permission.CAMERA';
const PERMISSION_MICROPHONE: Permissions = 'ohos.permission.MICROPHONE';

interface RtcVideoCreationParams {
  role?: string;
  remoteUserId?: string;
}

interface RtcVideoBinding {
  controller: AliRtcXComponentController;
  surfaceId: string;
  remoteUserId?: string;
}

interface RtcMediaPermissionRequestResult {
  state: string;
  promptHandled: boolean;
}

export default class PetNoteRtcPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private pluginBinding: FlutterPluginBinding | null = null;
  private ability: UIAbility | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private engine: AliRtcEngine | null = null;
  private cameraEnabled: boolean = true;
  private microphoneEnabled: boolean = true;
  private remoteUserId: string | null = null;
  private localVideo: RtcVideoBinding | null = null;
  private remoteVideo: RtcVideoBinding | null = null;
  private rtcEventListener: AliRtcEngineEventListener | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    binding.getPlatformViewRegistry()
      .registerViewFactory(VIDEO_VIEW_TYPE, new PetNoteRtcVideoViewFactory(this));
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

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.abilityBinding = null;
    this.ability = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'initialize':
          this.ensureEngine();
          result.success(null);
          break;
        case 'getMediaPermissionState':
          this.replyMediaPermissionState(result);
          break;
        case 'requestMediaPermission':
          this.replyRequestMediaPermission(result);
          break;
        case 'openMediaPermissionSettings':
          this.replyOpenMediaPermissionSettings(result);
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

  private replyMediaPermissionState(result: MethodResult): void {
    this.mediaPermissionState()
      .then((state: string) => {
        result.success(state);
      })
      .catch(() => {
        result.success('unknown');
      });
  }

  private replyRequestMediaPermission(result: MethodResult): void {
    const ability = this.ability;
    if (ability == null) {
      result.success({ state: 'unsupported', promptHandled: false });
      return;
    }
    this.requestMediaPermissions(ability)
      .then((requestResult: RtcMediaPermissionRequestResult) => {
        result.success(requestResult);
      })
      .catch(() => {
        result.success({ state: 'unknown', promptHandled: false });
      });
  }

  private replyOpenMediaPermissionSettings(result: MethodResult): void {
    const ability = this.ability;
    if (ability == null) {
      result.success('unsupported');
      return;
    }
    const permissions: Array<Permissions> = [PERMISSION_CAMERA, PERMISSION_MICROPHONE];
    const atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionOnSetting(ability.context, permissions)
      .then(() => {
        result.success('opened');
      })
      .catch(() => {
        result.success('failed');
      });
  }

  private async mediaPermissionState(): Promise<string> {
    const ability = this.ability;
    if (ability == null) {
      return 'unsupported';
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = this.accessTokenId();
    const cameraGranted = atManager.checkAccessTokenSync(tokenId, PERMISSION_CAMERA) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    const microphoneGranted = atManager.checkAccessTokenSync(tokenId, PERMISSION_MICROPHONE) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    return cameraGranted && microphoneGranted ? 'authorized' : 'denied';
  }

  private async requestMediaPermissions(ability: UIAbility): Promise<RtcMediaPermissionRequestResult> {
    const permissions: Array<Permissions> = [PERMISSION_CAMERA, PERMISSION_MICROPHONE];
    const atManager = abilityAccessCtrl.createAtManager();
    const requestResult = await atManager.requestPermissionsFromUser(ability.context, permissions) as PermissionRequestResult;
    const authResults = requestResult.authResults ?? [];
    const granted = authResults.length > 0 &&
      authResults.every((item: number) => item === MEDIA_PERMISSION_GRANTED);
    const afterState = await this.confirmMediaPermissionState();
    return {
      state: afterState === 'authorized' || granted ? 'authorized' : 'denied',
      promptHandled: this.didShowPermissionDialog(requestResult),
    };
  }

  private didShowPermissionDialog(requestResult: PermissionRequestResult): boolean {
    const dialogShownResults = requestResult.dialogShownResults ?? [];
    return dialogShownResults.some((item: boolean) => item);
  }

  private async confirmMediaPermissionState(): Promise<string> {
    let state = await this.mediaPermissionState();
    if (state === 'authorized') {
      return state;
    }
    await this.sleep(220);
    state = await this.mediaPermissionState();
    if (state === 'authorized') {
      return state;
    }
    await this.sleep(380);
    return this.mediaPermissionState();
  }

  private accessTokenId(): number {
    return bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
    ).appInfo.accessTokenId;
  }

  private sleep(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), milliseconds);
    });
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
    this.engine.setRtcEngineEventListener(this.ensureRtcEventListener());
    return this.engine;
  }

  private ensureRtcEventListener(): AliRtcEngineEventListener {
    if (this.rtcEventListener != null) {
      return this.rtcEventListener;
    }
    this.rtcEventListener = new AliRtcEngineEventListener()
      .onRemoteUserOnline((uid: string, online: boolean) => {
        if (online) {
          this.deferRemoteMediaAvailable(uid);
        }
      })
      .onRemoteTrackAvailableNotify((uid: string, audioTrack: AliRtcAudioTrack, videoTrack: AliRtcVideoTrack) => {
        this.deferRemoteMediaAvailable(uid);
      });
    return this.rtcEventListener;
  }

  private join(call: MethodCall, result: MethodResult): void {
    const engine = this.ensureEngine();
    const singleToken = this.requireString(call, 'singleToken');
    this.configureVideoEncoder(call, engine);
    const channelId = this.requireString(call, 'channelId');
    const userId = this.requireString(call, 'userId');
    this.remoteUserId = this.requireString(call, 'remoteUserId');
    engine.setChannelProfile(AliRtcChannelProfile.AliEngineInteractiveLive);
    engine.setClientRole(AliRtcClientRole.AliEngineClientRoleInteractive);
    engine.setDefaultSubscribeAllRemoteAudioStreams(true);
    engine.setDefaultSubscribeAllRemoteVideoStreams(true);
    this.attachLocalView(engine);
    this.attachRemoteView(engine);
    engine.joinChannelWithToken(singleToken, channelId, userId, '');
    engine.publishLocalAudioStream(this.microphoneEnabled);
    engine.publishLocalVideoStream(this.cameraEnabled);
    engine.subscribeAllRemoteAudioStreams(true);
    engine.subscribeAllRemoteVideoStreams(true);
    this.subscribeRemoteMedia(engine, this.remoteUserId);
    this.attachRemoteView(engine);
    result.success(null);
  }

  bindVideoView(
    role: string,
    remoteUserId: string | null,
    controller: AliRtcXComponentController,
    surfaceId: string,
  ): void {
    if (role === 'local') {
      this.localVideo = { controller, surfaceId };
    } else if (role === 'remote') {
      const resolvedRemoteUserId = remoteUserId ?? this.remoteUserId ?? undefined;
      this.remoteUserId = resolvedRemoteUserId ?? this.remoteUserId;
      this.remoteVideo = { controller, surfaceId, remoteUserId: resolvedRemoteUserId };
    } else {
      return;
    }
    const engine = this.ensureEngine();
    if (role === 'local') {
      this.attachLocalView(engine);
    } else {
      this.attachRemoteView(engine);
    }
  }

  unbindVideoView(controller: AliRtcXComponentController): void {
    const engine = this.engine;
    if (this.localVideo?.controller === controller) {
      if (engine != null) {
        engine.stopPreview();
        engine.setLocalViewConfig(
          this.makeCanvas(this.localVideo.surfaceId),
          null,
          AliRtcVideoTrack.AliEngineVideoTrackCamera,
        );
      }
      this.localVideo = null;
    }
    if (this.remoteVideo?.controller === controller) {
      const remoteUserId = this.remoteVideo.remoteUserId ?? this.remoteUserId;
      if (engine != null && remoteUserId != null) {
        engine.setRemoteViewConfig(
          this.makeCanvas(this.remoteVideo.surfaceId),
          null,
          remoteUserId,
          AliRtcVideoTrack.AliEngineVideoTrackCamera,
        );
      }
      this.remoteVideo = null;
    }
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

  private attachLocalView(engine: AliRtcEngine): void {
    const video = this.localVideo;
    if (video == null) {
      return;
    }
    engine.setLocalViewConfig(
      this.makeCanvas(video.surfaceId),
      video.controller,
      AliRtcVideoTrack.AliEngineVideoTrackCamera,
    );
    engine.startPreview();
  }

  private attachRemoteView(engine: AliRtcEngine): void {
    const video = this.remoteVideo;
    const remoteUserId = video?.remoteUserId ?? this.remoteUserId;
    if (video == null || remoteUserId == null) {
      return;
    }
    engine.setRemoteViewConfig(
      this.makeCanvas(video.surfaceId),
      video.controller,
      remoteUserId,
      AliRtcVideoTrack.AliEngineVideoTrackCamera,
    );
  }

  private handleRemoteMediaAvailable(uid: string): void {
    if (uid !== this.remoteUserId) {
      return;
    }
    const engine = this.engine;
    if (engine == null) {
      return;
    }
    this.subscribeRemoteMedia(engine, uid);
    this.attachRemoteView(engine);
  }

  private deferRemoteMediaAvailable(uid: string): void {
    setTimeout(() => {
      this.handleRemoteMediaAvailable(uid);
    }, 0);
  }

  private subscribeRemoteMedia(engine: AliRtcEngine, uid: string): void {
    engine.subscribeRemoteMediaStream(
      uid,
      AliRtcVideoTrack.AliEngineVideoTrackCamera,
      true,
      true,
    );
  }

  private makeCanvas(surfaceId: string): AliRtcVideoCanvas {
    const canvas: AliRtcVideoCanvas = new AliRtcVideoCanvas();
    canvas.surfaceId = surfaceId;
    canvas.renderMode = AliRtcRenderMode.AliEngineRenderModeAuto;
    return canvas;
  }

  private releaseEngine(): void {
    const engine = this.engine;
    if (engine != null) {
      if (this.localVideo != null) {
        engine.stopPreview();
        engine.setLocalViewConfig(
          this.makeCanvas(this.localVideo.surfaceId),
          null,
          AliRtcVideoTrack.AliEngineVideoTrackCamera,
        );
      }
      const remoteUserId = this.remoteVideo?.remoteUserId ?? this.remoteUserId;
      if (this.remoteVideo != null && remoteUserId != null) {
        engine.setRemoteViewConfig(
          this.makeCanvas(this.remoteVideo.surfaceId),
          null,
          remoteUserId,
          AliRtcVideoTrack.AliEngineVideoTrackCamera,
        );
      }
      engine.leaveChannel();
      engine.setRtcEngineEventListener(null);
    }
    AliRtcEngine.destroyInstance();
    this.engine = null;
    this.rtcEventListener = null;
    this.remoteUserId = null;
    this.localVideo = null;
    this.remoteVideo = null;
  }
}

class PetNoteRtcVideoViewFactory extends PlatformViewFactory {
  private readonly plugin: PetNoteRtcPlugin;

  constructor(plugin: PetNoteRtcPlugin) {
    super(StandardMessageCodec.INSTANCE);
    this.plugin = plugin;
  }

  create(_context: common.Context, viewId: number, args: Any): PlatformView {
    return new PetNoteRtcVideoPlatformView(this.plugin, viewId, args);
  }
}

class PetNoteRtcVideoPlatformView extends PlatformView {
  private readonly state: PetNoteRtcVideoViewState;
  private readonly plugin: PetNoteRtcPlugin;

  constructor(plugin: PetNoteRtcPlugin, viewId: number, args: Any) {
    super();
    this.plugin = plugin;
    this.state = new PetNoteRtcVideoViewState(viewId);
    this.applyCreationParams(args);
    this.plugin.bindVideoView(
      this.state.role,
      this.state.remoteUserId,
      this.state.controller,
      this.state.surfaceId,
    );
  }

  getType(): string {
    return VIDEO_VIEW_TYPE;
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(PetNoteRtcVideoViewBuilder);
  }

  getState(): PetNoteRtcVideoViewState {
    return this.state;
  }

  dispose(): void {
    this.plugin.unbindVideoView(this.state.controller);
  }

  private applyCreationParams(args: Any): void {
    const params = args as RtcVideoCreationParams;
    if (params == null) {
      return;
    }
    if (params.role === 'local' || params.role === 'remote') {
      this.state.role = params.role;
    }
    if (typeof params.remoteUserId === 'string' && params.remoteUserId.trim().length > 0) {
      this.state.remoteUserId = params.remoteUserId;
    }
  }
}

@Observed
class PetNoteRtcVideoViewState {
  role: string = 'remote';
  remoteUserId: string | null = null;
  readonly surfaceId: string;
  readonly controller: AliRtcXComponentController = new AliRtcXComponentController();

  constructor(viewId: number) {
    this.surfaceId = `petnote_rtc_video_${viewId}`;
  }
}

@Builder
function PetNoteRtcVideoViewBuilder(params: Params): void {
  PetNoteRtcVideoView({
    state: (params.platformView as PetNoteRtcVideoPlatformView).getState(),
  })
}

@Component
struct PetNoteRtcVideoView {
  @ObjectLink state: PetNoteRtcVideoViewState;

  build() {
    XComponent({
      id: this.state.surfaceId,
      type: XComponentType.SURFACE,
      controller: this.state.controller,
    })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
  }
}
