
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import PetNoteNotificationPlugin from '../plugins/PetNoteNotificationPlugin';

export default class EntryAbility extends FlutterAbility {
  override isDefaultFullScreen(): boolean {
    return true;
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new PetNoteNotificationPlugin())
  }
}
