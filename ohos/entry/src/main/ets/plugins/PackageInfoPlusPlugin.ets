import bundleManager from '@ohos.bundle.bundleManager';
import resourceManager from '@ohos.resourceManager';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG = 'PackageInfoPlusPlugin';
const CHANNEL_NAME = 'dev.fluttercommunity.plus/package_info';

interface PackageInfoApplicationInfo {
  labelId?: number;
  name?: string;
}

interface PackageInfoBundleInfo {
  name?: string;
  versionName?: string;
  versionCode?: number | bigint;
  installTime?: number | bigint;
  updateTime?: number | bigint;
  appInfo?: PackageInfoApplicationInfo;
}

interface PackageInfoBundleInfoSource {
  name: string;
  versionName: string;
  versionCode: number;
  installTime: number;
  updateTime: number;
  appInfo?: PackageInfoApplicationInfo;
}

class PackageInfoPayload {
  appName: string = '';
  packageName: string = '';
  version: string = '';
  buildNumber: string = '';
  buildSignature: string = '';
  installerStore: string | null = null;
  installTime: string | null = null;
  updateTime: string | null = null;
}

export default class PackageInfoPlusPlugin implements FlutterPlugin, MethodCallHandler {
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
    if (call.method !== 'getAll') {
      result.notImplemented();
      return;
    }

    try {
      result.success(this.buildPackageInfo());
    } catch (error) {
      result.error('package_info_error', '读取应用信息失败', null);
    }
  }

  private buildPackageInfo(): PackageInfoPayload {
    const bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION;
    const bundleInfoSource = bundleManager.getBundleInfoForSelfSync(bundleFlags) as PackageInfoBundleInfoSource;
    const bundleInfo: PackageInfoBundleInfo = {
      name: bundleInfoSource.name,
      versionName: bundleInfoSource.versionName,
      versionCode: bundleInfoSource.versionCode,
      installTime: bundleInfoSource.installTime,
      updateTime: bundleInfoSource.updateTime,
      appInfo: bundleInfoSource.appInfo,
    };
    const appInfo = bundleInfo.appInfo;
    const resourceManager = this.pluginBinding?.getApplicationContext().resourceManager;
    const appName = this.resolveAppName(appInfo, resourceManager);
    const payload = new PackageInfoPayload();
    payload.appName = appName;
    payload.packageName = bundleInfo.name ?? '';
    payload.version = bundleInfo.versionName ?? '';
    payload.buildNumber = this.readNumberString(bundleInfo.versionCode) ?? '';
    payload.installTime = this.readNumberString(bundleInfo.installTime);
    payload.updateTime = this.readNumberString(bundleInfo.updateTime);
    return payload;
  }

  private resolveAppName(
    appInfo: PackageInfoApplicationInfo | undefined,
    resourceManagerInstance: resourceManager.ResourceManager | undefined,
  ): string {
    const labelId = appInfo?.labelId;
    if (typeof labelId === 'number' && resourceManagerInstance != null) {
      try {
        return resourceManagerInstance.getStringSync(labelId);
      } catch (error) {
      }
    }

    if (resourceManagerInstance != null) {
      try {
        return resourceManagerInstance.getStringByNameSync('EntryAbility_label');
      } catch (error) {
      }
    }

    const fallbackName = appInfo?.name;
    if (typeof fallbackName === 'string' && fallbackName.length > 0) {
      return fallbackName;
    }

    return 'PetNote';
  }

  private readNumberString(value: number | bigint | undefined): string | null {
    if (typeof value === 'number') {
      return value.toString();
    }
    if (typeof value === 'bigint') {
      return value.toString();
    }
    return null;
  }
}
