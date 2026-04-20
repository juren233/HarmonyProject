import { FlutterEngine } from '@ohos/flutter_ohos';
import PackageInfoPlusPlugin from './PackageInfoPlusPlugin';

export class ProjectPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new PackageInfoPlusPlugin());
  }
}
