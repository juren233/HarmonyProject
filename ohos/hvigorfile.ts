import path from 'path'
import { appTasks } from '@ohos/hvigor-ohos-plugin';
// Keep the `flutter-hvigor-plugin` token so Flutter continues using the Hvigor TS builder.
import { flutterHvigorPlugin } from '../tooling/ohos-hvigor-plugin';

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname))]         /* Custom plugin to extend the functionality of Hvigor. */
}
