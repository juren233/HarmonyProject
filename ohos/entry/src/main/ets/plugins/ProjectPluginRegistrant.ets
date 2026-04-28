import { FlutterEngine } from '@ohos/flutter_ohos';
import PackageInfoPlusPlugin from './PackageInfoPlusPlugin';
import PetNoteAppDirectoryPlugin from './PetNoteAppDirectoryPlugin';
import PetNoteHarmonyNativeDockPlugin from './PetNoteHarmonyNativeDockPlugin';
import PetNoteNativePetPhotoPickerPlugin from './PetNoteNativePetPhotoPickerPlugin';
import PetNoteNotificationPlugin from './PetNoteNotificationPlugin';
import SharedPreferencesPlugin from './SharedPreferencesPlugin';

export class ProjectPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new PackageInfoPlusPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteAppDirectoryPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteHarmonyNativeDockPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteNativePetPhotoPickerPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteNotificationPlugin());
    flutterEngine.getPlugins()?.add(new SharedPreferencesPlugin());
  }
}
