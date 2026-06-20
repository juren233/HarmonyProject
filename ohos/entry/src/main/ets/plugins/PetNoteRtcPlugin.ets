import { abilityAccessCtrl, bundleManager, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import common from '@ohos.app.ability.common';
import UIAbility from '@ohos.app.ability.UIAbility';
import { DingRtc, DingRtcConstants, DingRtcEventListener, DingRtcSDK, DingRtcVideoView } from '@dingrtc/dingrtc';
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
  private engine: DingRtc | null = null;
  private cameraEnabled: boolean = true;
  private microphoneEnabled: boolean = true;
  private expectedRemoteUserId: string | null = null;
  private activeRemoteUserId: string | null = null;
  private localVideo: RtcVideoBinding | null = null;
  private remoteVideo: RtcVideoBinding | null = null;
  private rtcEventListener: DingRtcEventListener | null = null;
  private pendingJoinResult: MethodResult | null = null;
  private joinTimeoutId: number = -1;

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
          this.cancelPendingJoin('rtc join was cancelled by leave');
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
          this.cancelPendingJoin('rtc join was cancelled by dispose');
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

  private ensureEngine(): DingRtc {
    if (this.engine != null) {
      return this.engine;
    }
    const context = this.pluginBinding?.getApplicationContext();
    if (context == null) {
      throw new Error('应用上下文不可用');
    }
    this.engine = DingRtcSDK.create(context);
    this.engine.setEventListener(this.ensureRtcEventListener());
    return this.engine;
  }

  private ensureRtcEventListener(): DingRtcEventListener {
    if (this.rtcEventListener != null) {
      return this.rtcEventListener;
    }
    this.rtcEventListener = new PetNoteDingRtcEventListener(this);
    return this.rtcEventListener;
  }

  private join(call: MethodCall, result: MethodResult): void {
    if (this.pendingJoinResult != null) {
      this.pendingJoinResult.error('rtc_join_replaced', 'rtc join was replaced by a new join request', null);
    }
    this.pendingJoinResult = result;
    const engine = this.ensureEngine();
    const token = this.requireString(call, 'token');
    const appId = this.requireString(call, 'appId');
    this.configureVideoEncoder(call, engine);
    const channelId = this.requireString(call, 'channelId');
    const userId = this.requireString(call, 'userId');
    this.expectedRemoteUserId = this.requireString(call, 'remoteUserId');
    this.activeRemoteUserId = null;
    this.attachLocalView(engine);
    this.attachRemoteView(engine);
    this.log(`join requested channelId=${channelId} userId=${userId} remoteUserId=${this.expectedRemoteUserId}`);
    const authInfo = new DingRtcConstants.AuthInfo();
    authInfo.channelId = channelId;
    authInfo.userId = userId;
    authInfo.appId = appId;
    authInfo.token = token;
    const joinResult = engine.joinChannel(authInfo, userId);
    this.logResult('joinChannel', joinResult ?? -1);
    if (joinResult !== 0) {
      this.completeJoinWithError(joinResult, `join rtc channel failed: ${joinResult}`);
      return;
    }
    this.scheduleJoinTimeout();
  }

  handleJoinChannelResult(code: number, channel: string): void {
    if (this.pendingJoinResult == null) {
      return;
    }
    if (code !== 0) {
      this.completeJoinWithError(code, `join rtc channel failed asynchronously: ${code} channel=${channel}`);
      return;
    }
    const engine = this.engine;
    if (engine == null) {
      this.completeJoinWithError(0, 'join rtc channel succeeded after engine was released');
      return;
    }
    this.logResult('publishLocalAudioStream', engine.publishLocalAudioStream(this.microphoneEnabled));
    this.logResult('publishLocalVideoStream', engine.publishLocalVideoStream(this.cameraEnabled));
    this.logResult('subscribeAllRemoteAudioStreams', engine.subscribeAllRemoteAudioStreams(true));
    this.logResult('subscribeAllRemoteVideoStreams', engine.subscribeAllRemoteVideoStreams(true));
    const remoteUserId = this.currentRemoteUserId();
    if (remoteUserId != null) {
      this.subscribeRemoteMedia(engine, remoteUserId);
    }
    this.attachRemoteView(engine);
    const pendingResult = this.pendingJoinResult;
    this.pendingJoinResult = null;
    this.cancelJoinTimeout();
    pendingResult?.success(null);
  }

  completeJoinWithError(code: number, message: string): void {
    const pendingResult = this.pendingJoinResult;
    if (pendingResult == null) {
      return;
    }
    this.pendingJoinResult = null;
    this.cancelJoinTimeout();
    this.releaseEngine();
    pendingResult.error('rtc_join_failed', `${message} (code=${code})`, null);
  }

  private cancelPendingJoin(message: string): void {
    const pendingResult = this.pendingJoinResult;
    if (pendingResult == null) {
      return;
    }
    this.pendingJoinResult = null;
    this.cancelJoinTimeout();
    pendingResult.error('rtc_join_cancelled', message, null);
  }

  private scheduleJoinTimeout(): void {
    this.cancelJoinTimeout();
    this.joinTimeoutId = setTimeout(() => {
      this.completeJoinWithError(-1, 'join rtc channel timed out');
    }, 15000);
  }

  private cancelJoinTimeout(): void {
    if (this.joinTimeoutId >= 0) {
      clearTimeout(this.joinTimeoutId);
      this.joinTimeoutId = -1;
    }
  }

  bindVideoView(
    role: string,
    remoteUserId: string | null,
    surfaceId: string,
  ): void {
    if (role === 'local') {
      this.localVideo = { surfaceId };
    } else if (role === 'remote') {
      const resolvedRemoteUserId = remoteUserId ?? this.currentRemoteUserId() ?? undefined;
      this.expectedRemoteUserId = remoteUserId ?? this.expectedRemoteUserId;
      this.remoteVideo = { surfaceId, remoteUserId: resolvedRemoteUserId };
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

  unbindVideoView(surfaceId: string): void {
    const engine = this.engine;
    if (this.localVideo?.surfaceId === surfaceId) {
      if (engine != null) {
        engine.stopPreview();
        engine.setLocalViewConfig(
          this.makeCanvas(this.localVideo.surfaceId),
          DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
        );
      }
      this.localVideo = null;
    }
    if (this.remoteVideo?.surfaceId === surfaceId) {
      const remoteUserId = this.currentRemoteUserId(this.remoteVideo.remoteUserId);
      if (engine != null && remoteUserId != null) {
        engine.setRemoteViewConfig(
          this.makeCanvas(this.remoteVideo.surfaceId),
          remoteUserId,
          DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
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

  private configureVideoEncoder(call: MethodCall, engine: DingRtc): void {
    const width = call.argument('videoWidth') as number | undefined;
    const height = call.argument('videoHeight') as number | undefined;
    if (width !== 1280 || height !== 720) {
      throw new Error('RTC 画质必须为 720P');
    }
    const config = new DingRtcConstants.RtcEngineVideoEncoderConfiguration(width, height);
    engine.setVideoEncoderConfiguration(config);
    this.logResult('setVideoEncoderConfiguration', 0);
  }

  private attachLocalView(engine: DingRtc): void {
    const video = this.localVideo;
    if (video == null) {
      return;
    }
    this.logResult(
      'setLocalViewConfig',
      engine.setLocalViewConfig(
        this.makeCanvas(video.surfaceId),
        DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
      ),
    );
    this.logResult('startPreview', engine.startPreview());
  }

  private attachRemoteView(engine: DingRtc): void {
    const video = this.remoteVideo;
    const remoteUserId = this.currentRemoteUserId(video?.remoteUserId);
    if (video == null || remoteUserId == null) {
      return;
    }
    this.logResult(
      'setRemoteViewConfig',
      engine.setRemoteViewConfig(
        this.makeCanvas(video.surfaceId),
        remoteUserId,
        DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
      ),
    );
  }

  private handleRemoteMediaAvailable(uid: string): void {
    const engine = this.engine;
    if (engine == null) {
      return;
    }
    this.activeRemoteUserId = uid;
    this.subscribeRemoteMedia(engine, uid);
    this.attachRemoteView(engine);
  }

  deferRemoteMediaAvailable(uid: string): void {
    setTimeout(() => {
      this.handleRemoteMediaAvailable(uid);
    }, 0);
  }

  private subscribeRemoteMedia(engine: DingRtc, uid: string): void {
    this.logResult(
      'subscribeRemoteVideoStream',
      engine.subscribeRemoteVideoStream(
        uid,
        DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
        true,
      ),
    );
  }

  private logResult(operation: string, code: number): void {
    this.log(`${operation} result=${code}`);
  }

  private log(message: string): void {
    console.info(`[${TAG}] ${message}`);
  }

  logRtcEvent(message: string): void {
    this.log(message);
  }

  private makeCanvas(surfaceId: string): DingRtcConstants.RtcEngineVideoCanvas {
    const canvas: DingRtcConstants.RtcEngineVideoCanvas = { xComponentId: surfaceId };
    return canvas;
  }

  private releaseEngine(): void {
    this.cancelJoinTimeout();
    const engine = this.engine;
    if (engine != null) {
      if (this.localVideo != null) {
        engine.stopPreview();
        engine.setLocalViewConfig(
          this.makeCanvas(this.localVideo.surfaceId),
          DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
        );
      }
      const remoteUserId = this.currentRemoteUserId(this.remoteVideo?.remoteUserId);
      if (this.remoteVideo != null && remoteUserId != null) {
        engine.setRemoteViewConfig(
          this.makeCanvas(this.remoteVideo.surfaceId),
          remoteUserId,
          DingRtcConstants.RtcEngineVideoTrack.RtcEngineVideoTrackCamera,
        );
      }
      engine.leaveChannel();
    }
    engine?.release();
    this.engine = null;
    this.rtcEventListener = null;
    this.expectedRemoteUserId = null;
    this.activeRemoteUserId = null;
    this.localVideo = null;
    this.remoteVideo = null;
  }

  private currentRemoteUserId(fallback?: string): string | null {
    return this.activeRemoteUserId ?? fallback ?? this.expectedRemoteUserId;
  }
}

class PetNoteDingRtcEventListener extends DingRtcEventListener {
  private readonly plugin: PetNoteRtcPlugin;

  constructor(plugin: PetNoteRtcPlugin) {
    super();
    this.plugin = plugin;
  }

  onJoinChannelResult(result: number, channel: string, userId: string, elapsed: number): void {
    this.plugin.logRtcEvent(`onJoinChannelResult result=${result} channel=${channel} userId=${userId} elapsed=${elapsed}`);
    this.plugin.handleJoinChannelResult(result, channel);
  }

  onOccurError(error: number, message: string): void {
    this.plugin.logRtcEvent(`onOccurError error=${error} message=${message}`);
    this.plugin.completeJoinWithError(error, message);
  }

  onRemoteUserOnLineNotify(uid: string, elapsed: number): void {
    this.plugin.logRtcEvent(`onRemoteUserOnLineNotify uid=${uid} elapsed=${elapsed}`);
    this.plugin.deferRemoteMediaAvailable(uid);
  }

  onRemoteTrackAvailableNotify(
    uid: string,
    audioTrack: DingRtcConstants.RtcEngineAudioTrack,
    videoTrack: DingRtcConstants.RtcEngineVideoTrack,
  ): void {
    this.plugin.logRtcEvent(`onRemoteTrackAvailableNotify uid=${uid} audio=${audioTrack} video=${videoTrack}`);
    this.plugin.deferRemoteMediaAvailable(uid);
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
    this.plugin.unbindVideoView(this.state.surfaceId);
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
    DingRtcVideoView({
      canvasId: this.state.surfaceId,
      onLoad: (() => {
        console.info(`[${TAG}] surface create ${this.state.surfaceId}`);
      }),
      onDestroy: (() => {
        console.info(`[${TAG}] surface release ${this.state.surfaceId}`);
      }),
    })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
  }
}
