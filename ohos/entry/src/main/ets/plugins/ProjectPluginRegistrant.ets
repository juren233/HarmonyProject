import { FlutterEngine } from '@ohos/flutter_ohos';
import PackageInfoPlusPlugin from './PackageInfoPlusPlugin';
import PetNoteNotificationPlugin from './PetNoteNotificationPlugin';
import SharedPreferencesPlugin from './SharedPreferencesPlugin';

export class ProjectPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new PackageInfoPlusPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteNotificationPlugin());
    flutterEngine.getPlugins()?.add(new SharedPreferencesPlugin());
  }
}
