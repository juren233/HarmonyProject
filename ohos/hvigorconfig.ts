import path from 'path'
// Keep the `flutter-hvigor-plugin` token so Flutter continues using the Hvigor TS builder.
import { injectNativeModules } from '../tooling/ohos-hvigor-plugin';

injectNativeModules(__dirname, path.dirname(__dirname))
