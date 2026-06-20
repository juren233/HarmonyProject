import { FlutterEngine } from '@ohos/flutter_ohos';
import KeepAlivePlugin from './KeepAlivePlugin';
import PackageInfoPlusPlugin from './PackageInfoPlusPlugin';
import PetNoteAiSecretStorePlugin from './PetNoteAiSecretStorePlugin';
import PetNoteAppDirectoryPlugin from './PetNoteAppDirectoryPlugin';
import PetNoteDataPackageFileAccessPlugin from './PetNoteDataPackageFileAccessPlugin';
import PetNoteHarmonyNativeDockPlugin from './PetNoteHarmonyNativeDockPlugin';
import PetNoteInteractionHapticsPlugin from './PetNoteInteractionHapticsPlugin';
import PetNoteNotificationPlugin from './PetNoteNotificationPlugin';
import PetNotePhotoPickerPlugin from './PetNotePhotoPickerPlugin';
import PetNoteRtcPlugin from './PetNoteRtcPlugin';
import SharedPreferencesPlugin from './SharedPreferencesPlugin';

export class ProjectPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new KeepAlivePlugin());
    flutterEngine.getPlugins()?.add(new PackageInfoPlusPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteAiSecretStorePlugin());
    flutterEngine.getPlugins()?.add(new PetNoteAppDirectoryPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteDataPackageFileAccessPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteHarmonyNativeDockPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteInteractionHapticsPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteNotificationPlugin());
    flutterEngine.getPlugins()?.add(new PetNotePhotoPickerPlugin());
    flutterEngine.getPlugins()?.add(new PetNoteRtcPlugin());
    flutterEngine.getPlugins()?.add(new SharedPreferencesPlugin());
  }
}
