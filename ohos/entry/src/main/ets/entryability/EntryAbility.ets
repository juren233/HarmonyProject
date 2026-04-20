
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { ProjectPluginRegistrant } from '../plugins/ProjectPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  override isDefaultFullScreen(): boolean {
    return true;
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    ProjectPluginRegistrant.registerWith(flutterEngine)
  }
}
