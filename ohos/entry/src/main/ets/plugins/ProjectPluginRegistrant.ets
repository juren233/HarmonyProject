import { FlutterEngine } from '@ohos/flutter_ohos';
import PackageInfoPlusPlugin from './PackageInfoPlusPlugin';
import PetNoteNotificationPlugin from './PetNoteNotificationPlugin';

export class ProjectPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new PackageInfoPlusPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteNotificationPlugin());
  }
}
