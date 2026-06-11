import fs from 'fs';
import path from 'path'
import { getNode } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
// Keep the `flutter-hvigor-plugin` token so Flutter continues using the Hvigor TS builder.
import { flutterHvigorPlugin } from '../tooling/ohos-hvigor-plugin';

// 本地签名注入：DevEco 一键运行需要设备绑定的自动签名材料，但共享基线
// build-profile.json5 不接受本机绝对路径与密文。把 DevEco 自动签名生成的
// app.signingConfigs 数组原样存入未跟踪的 ohos/local-signing.json（严格 JSON），
// 构建评估期在内存中覆盖签名配置；文件不存在时回退共享基线签名
// （CI / 新机器 / 社区证书链不受影响），基线文件始终保持干净。
const localSigningFile = path.resolve(__dirname, 'local-signing.json');

getNode(__filename).afterNodeEvaluate(node => {
    if (!fs.existsSync(localSigningFile)) {
        return;
    }
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    if (!appContext) {
        return;
    }
    const buildProfile = appContext.getBuildProfileOpt();
    buildProfile['app']['signingConfigs'] =
        JSON.parse(fs.readFileSync(localSigningFile, 'utf-8'));
    appContext.setBuildProfileOpt(buildProfile);
});

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname))]         /* Custom plugin to extend the functionality of Hvigor. */
}
