import fs from 'fs'
import path from 'path'
import { platform } from 'process'
import { execSync } from 'child_process'
import { OhosAppContext, OhosHapContext, OhosHarContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin'
import { hvigor, HvigorNode, HvigorPlugin } from '@ohos/hvigor'
import { relativePath, copyDirectory, listFiles, realFilePath } from '../util/file-util'
import { getParameter, getParameters } from '../util/parameter-util'
import { loadProperties } from '../util/properties-util'
import { toCamelCase } from '../util/string-util'

/** The platforms that can be passed to the `-p target-platform` flag. */
const PLATFORM_ARM32 = 'ohos-arm'
const PLATFORM_ARM64 = 'ohos-arm64'
const PLATFORM_X86_64 = 'ohos-x64'

/** The ABI architectures supported by Flutter. */
const ARCH_ARM32 = "armeabi-v7a"
const ARCH_ARM64 = "arm64-v8a"
const ARCH_X86_64 = "x86_64"

/** Maps platforms to ABI architectures. */
const PLATFORM_ARCH_MAP: Record<string, string> = {
  [PLATFORM_ARM32]: ARCH_ARM32,
  [PLATFORM_ARM64]: ARCH_ARM64,
  [PLATFORM_X86_64]: ARCH_X86_64,
}

/** When split is enabled, multiple APKs are generated per each ABI. */
const DEFAULT_PLATFORMS = [
  PLATFORM_ARM64,
  PLATFORM_X86_64
]

const TARGET_PLATFORM = 'TARGET_PLATFORM'
const REPO_OWNED_HVIGOR_PLUGIN_DEPENDENCY = 'file:../tooling/ohos-hvigor-plugin'

const localEngineHost = getParameter('LOCAL_ENGINE_HOST') // /xxx/engine/src/out/host_debug_unopt
const localEngineSrcPath = getParameter('FLUTTER_ENGINE') // /xxx/engine/src
const localEngine = getParameter('LOCAL_ENGINE') // /xxx/engine/src/out/ohos_debug_unopt_arm64

const FLUTTER_ASSETS_PATH = 'flutter_assets'
const MANAGED_FLUTTER_STATE_FILES = [
  'pubspec.lock',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.dart_tool/package_config.json',
  '.dart_tool/package_config_subset',
  '.dart_tool/package_graph.json',
  '.dart_tool/version',
  'android/local.properties',
]

function ensureParentDirectory(targetPath: string) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true })
}

function removePathIfExists(targetPath: string) {
  if (fs.existsSync(targetPath)) {
    fs.rmSync(targetPath, { recursive: true, force: true })
  }
}

const LOCKFILE_HOSTED_URL = 'https://pub.flutter-io.cn'

function normalizePubspecLockHostedUrl(targetPath: string) {
  if (path.basename(targetPath) !== 'pubspec.lock' || !fs.existsSync(targetPath)) {
    return
  }

  const content = fs.readFileSync(targetPath, 'utf-8')
  const normalizedContent = content.replace(/https:\/\/pub\.dev/g, LOCKFILE_HOSTED_URL)
  if (normalizedContent === content) {
    return
  }

  fs.writeFileSync(targetPath, normalizedContent, 'utf-8')
}

function copyFilePreservingParent(sourcePath: string, destinationPath: string) {
  ensureParentDirectory(destinationPath)
  fs.copyFileSync(sourcePath, destinationPath)
  normalizePubspecLockHostedUrl(destinationPath)
}

function getFlutterStateRoot(flutterProjectPath: string, stateName: string): string {
  return path.join(flutterProjectPath, '.tooling', 'flutter-state', stateName)
}

function getFlutterPluginsDependenciesPath(flutterProjectPath: string): string {
  const defaultPath = path.join(flutterProjectPath, '.flutter-plugins-dependencies')
  const ohosStatePath = path.join(getFlutterStateRoot(flutterProjectPath, 'ohos'), '.flutter-plugins-dependencies')
  if (
    normalizeComparablePath(ohosStatePath) !== normalizeComparablePath(defaultPath) &&
    fs.existsSync(ohosStatePath)
  ) {
    return ohosStatePath
  }

  return defaultPath
}

function backupManagedFlutterState(flutterProjectPath: string): string {
  const backupRoot = path.join(
    flutterProjectPath,
    '.tooling',
    'flutter-state',
    '.session-backups',
    `deveco-${Date.now()}`
  )
  fs.mkdirSync(backupRoot, { recursive: true })

  MANAGED_FLUTTER_STATE_FILES.forEach(relativePath => {
    const sourcePath = path.join(flutterProjectPath, relativePath)
    if (!fs.existsSync(sourcePath)) {
      return
    }
    copyFilePreservingParent(sourcePath, path.join(backupRoot, relativePath))
  })

  return backupRoot
}

function restoreManagedFlutterState(flutterProjectPath: string, restoreRoot: string): boolean {
  if (!fs.existsSync(restoreRoot)) {
    return false
  }

  MANAGED_FLUTTER_STATE_FILES.forEach(relativePath => {
    const sourcePath = path.join(restoreRoot, relativePath)
    const targetPath = path.join(flutterProjectPath, relativePath)
    if (fs.existsSync(sourcePath)) {
      copyFilePreservingParent(sourcePath, targetPath)
    } else {
      removePathIfExists(targetPath)
    }
  })

  return true
}

function cleanupManagedFlutterStateBackup(backupRoot: string) {
  removePathIfExists(backupRoot)
}

function restoreNamedFlutterState(flutterProjectPath: string, stateName: string): boolean {
  return restoreManagedFlutterState(flutterProjectPath, getFlutterStateRoot(flutterProjectPath, stateName))
}

function normalizeComparablePath(filePath: string): string {
  return path.normalize(filePath).replace(/\\/g, '/').toLowerCase()
}

function resolvePackageRootUri(flutterProjectPath: string, rootUri: string): string {
  if (rootUri.startsWith('file:///')) {
    return decodeURIComponent(rootUri.replace('file:///', ''))
  }
  if (rootUri.startsWith('file://')) {
    return decodeURIComponent(rootUri.replace('file://', ''))
  }
  return path.resolve(flutterProjectPath, rootUri)
}

function getFlutterProjectPackageName(flutterProjectPath: string): string | null {
  const pubspecPath = path.join(flutterProjectPath, 'pubspec.yaml')
  if (!fs.existsSync(pubspecPath)) {
    return null
  }

  try {
    const pubspecContent = fs.readFileSync(pubspecPath, 'utf-8')
    const match = pubspecContent.match(/^name:\s*([^\s#]+)\s*$/m)
    return match?.[1] ?? null
  } catch (error) {
    console.warn(`Failed to inspect pubspec.yaml for package name, refresh Flutter packages by default. ${error}`)
    return null
  }
}

function getFlutterProjectVersionInfo(flutterProjectPath: string): {
  versionName: string | null
  versionCode: string | null
} {
  const pubspecPath = path.join(flutterProjectPath, 'pubspec.yaml')
  if (!fs.existsSync(pubspecPath)) {
    return { versionName: null, versionCode: null }
  }

  try {
    const pubspecContent = fs.readFileSync(pubspecPath, 'utf-8')
    const versionMatch = pubspecContent.match(/^version:\s*([^\s#]+)\s*$/m)
    const versionValue = versionMatch?.[1]?.trim()
    if (!versionValue) {
      return { versionName: null, versionCode: null }
    }

    const [versionName, buildNumber = '1'] = versionValue.split('+', 2)
    if (!versionName) {
      return { versionName: null, versionCode: null }
    }
    if (!/^\d+$/.test(buildNumber)) {
      console.warn(`pubspec.yaml build number is not numeric: ${buildNumber}`)
      return { versionName: versionName.trim(), versionCode: null }
    }

    return {
      versionName: versionName.trim(),
      versionCode: buildNumber.trim(),
    }
  } catch (error) {
    console.warn(`Failed to inspect pubspec.yaml for version info. ${error}`)
    return { versionName: null, versionCode: null }
  }
}

function hasValidPackageGraphForCurrentProject(flutterProjectPath: string): boolean {
  const packageGraphPath = path.join(flutterProjectPath, '.dart_tool', 'package_graph.json')
  if (!fs.existsSync(packageGraphPath)) {
    return false
  }

  const projectPackageName = getFlutterProjectPackageName(flutterProjectPath)
  if (!projectPackageName) {
    return false
  }

  try {
    const packageGraph = JSON.parse(fs.readFileSync(packageGraphPath, 'utf-8'))
    const roots = Array.isArray(packageGraph.roots) ? packageGraph.roots : []
    const packages = Array.isArray(packageGraph.packages) ? packageGraph.packages : []
    const projectPackage = packages.find((pkg: { name?: string }) => pkg.name === projectPackageName)

    return (
      roots.includes(projectPackageName) &&
      !!projectPackage &&
      Array.isArray(projectPackage.dependencies)
    )
  } catch (error) {
    console.warn(`Failed to inspect package_graph.json, refresh Flutter packages by default. ${error}`)
    return false
  }
}

function shouldRefreshFlutterPackages(flutterProjectPath: string, sdkPath: string): boolean {
  const packageConfigPath = path.join(flutterProjectPath, '.dart_tool', 'package_config.json')
  if (!fs.existsSync(packageConfigPath)) {
    return true
  }

  if (!hasValidPackageGraphForCurrentProject(flutterProjectPath)) {
    return true
  }

  try {
    const packageConfig = JSON.parse(fs.readFileSync(packageConfigPath, 'utf-8'))
    const flutterPackage = packageConfig.packages?.find((pkg: { name?: string }) => pkg.name === 'flutter')
    if (!flutterPackage?.rootUri) {
      return true
    }

    const currentFlutterRoot = resolvePackageRootUri(flutterProjectPath, flutterPackage.rootUri)
    const expectedFlutterRoot = path.join(sdkPath, 'packages', 'flutter')
    return normalizeComparablePath(currentFlutterRoot) !== normalizeComparablePath(expectedFlutterRoot)
  } catch (error) {
    console.warn(`Failed to inspect package_config.json, refresh Flutter packages by default. ${error}`)
    return true
  }
}

function ensureFlutterPackages(flutterExecutablePath: string, flutterProjectPath: string, sdkPath: string) {
  if (!shouldRefreshFlutterPackages(flutterProjectPath, sdkPath)) {
    ensureRepoOwnedHvigorPlugin(flutterProjectPath)
    return
  }

  console.info('Refresh Flutter package config for OHOS IDE run start')
  execSync(
    `${flutterExecutablePath} pub get`,
    {
      cwd: flutterProjectPath,
      stdio: 'inherit',
      encoding: 'utf8',
    }
  )
  console.info('Refresh Flutter package config for OHOS IDE run end')
  ensureRepoOwnedHvigorPlugin(flutterProjectPath)
}

function switchToOhosFlutterState(
  flutterExecutablePath: string,
  flutterProjectPath: string,
  sdkPath: string,
): string {
  console.info('Backup Flutter shared state start')
  const sessionStateBackupRoot = backupManagedFlutterState(flutterProjectPath)
  console.info('Backup Flutter shared state end')

  console.info('Switch to OHOS Flutter state start')
  if (!restoreNamedFlutterState(flutterProjectPath, 'ohos')) {
    console.warn('OHOS Flutter state snapshot was not found; refresh package config directly.')
  }
  ensureFlutterPackages(flutterExecutablePath, flutterProjectPath, sdkPath)
  console.info('Switch to OHOS Flutter state end')

  return sessionStateBackupRoot
}

function restoreFlutterSharedState(flutterProjectPath: string, sessionStateBackupRoot: string) {
  console.info('Restore Flutter shared state start')
  const restoredSession = restoreManagedFlutterState(flutterProjectPath, sessionStateBackupRoot)
  if (!restoredSession) {
    restoreNamedFlutterState(flutterProjectPath, 'official')
  }
  cleanupManagedFlutterStateBackup(sessionStateBackupRoot)
  console.info('Restore Flutter shared state end')
}

function getOhosRoot(flutterProjectPath: string): string {
  return path.join(flutterProjectPath, 'ohos')
}


function getFlutterOhosStorePath(flutterProjectPath: string): string | null {
  const lockfilePath = path.join(getOhosRoot(flutterProjectPath), 'oh_modules', '.ohpm', 'lock.json5')
  if (!fs.existsSync(lockfilePath)) {
    return null
  }

  try {
    const lockfileContent = fs.readFileSync(lockfilePath, 'utf-8')
    const match = lockfileContent.match(/"@ohos\/flutter_ohos@file:[^"]+"\s*:\s*\{\s*"storePath"\s*:\s*"([^"]+)"/s)
    return match?.[1] ?? null
  } catch (error) {
    console.warn(`Failed to inspect OHPM lockfile for flutter_ohos store path. ${error}`)
    return null
  }
}

function clearStaleFlutterOhosArkTsCache(flutterProjectPath: string, expectedStorePath: string | null) {
  if (!expectedStorePath) {
    return
  }

  const entryBuildPath = path.join(getOhosRoot(flutterProjectPath), 'entry', 'build')
  if (!fs.existsSync(entryBuildPath)) {
    return
  }

  const normalizedExpectedStorePath = expectedStorePath.replace(/\\/g, '/')
  const cachedTsFiles = listFiles(entryBuildPath).filter(filePath => filePath.endsWith('.ts'))
  const hasStaleFlutterOhosStorePath = cachedTsFiles.some(filePath => {
    try {
      const fileContent = fs.readFileSync(filePath, 'utf-8')
      return fileContent.includes('@ohos/flutter_ohos') &&
        fileContent.includes('pkg_modules/.ohpm/') &&
        !fileContent.includes(normalizedExpectedStorePath)
    } catch (error) {
      console.warn(`Failed to inspect ArkTS cache file ${filePath}. ${error}`)
      return false
    }
  })

  if (!hasStaleFlutterOhosStorePath) {
    return
  }

  console.warn(`Detected stale flutter_ohos ArkTS cache. Clear incremental build outputs before rebuild.`)
  clearFlutterOhosArkTsBuildOutputs(flutterProjectPath)
}

function clearFlutterOhosArkTsBuildOutputs(flutterProjectPath: string) {
  const entryBuildPath = path.join(getOhosRoot(flutterProjectPath), 'entry', 'build')
  if (!fs.existsSync(entryBuildPath)) {
    return
  }

  const staleBuildPaths = [
    path.join(entryBuildPath, 'default', 'cache'),
    path.join(entryBuildPath, 'default', 'intermediates', 'loader'),
    path.join(entryBuildPath, 'default', 'intermediates', 'loader_out'),
    path.join(entryBuildPath, 'default', 'intermediates', 'source_map'),
    path.join(entryBuildPath, 'default', 'intermediates', 'package'),
    path.join(entryBuildPath, 'default', 'outputs'),
  ]
  staleBuildPaths.forEach(removePathIfExists)
}

function patchFlutterOhosFlutterViewAvoidAreaHandling(
  flutterProjectPath: string,
  flutterOhosStorePath: string | null,
): boolean {
  if (!flutterOhosStorePath) {
    return false
  }

  const flutterViewPath = path.join(
    getOhosRoot(flutterProjectPath),
    flutterOhosStorePath,
    'oh_modules',
    '@ohos',
    'flutter_ohos',
    'src',
    'main',
    'ets',
    'view',
    'FlutterView.ets',
  )
  if (!fs.existsSync(flutterViewPath)) {
    return false
  }

  const originalContent = fs.readFileSync(flutterViewPath, 'utf-8')
  const lineEnding = originalContent.includes('\r\n') ? '\r\n' : '\n'
  let content = originalContent.replace(/\r\n/g, '\n')

  content = content.replace('  private keyboardHeight: number = 0;\n', '')
  content = content.replace('    this.keyboardHeight = this.keyboardAvoidArea?.bottomRect.height ?? 0;\n', '')

  if (!content.includes('  private cloneAvoidArea(avoidArea?: window.AvoidArea): window.AvoidArea {')) {
    content = content.replace(
      "  setTouchSlopCallbackValue(callback: callbackNumber) {\n    this.callbackValue = callback;\n  }\n\n",
      "  setTouchSlopCallbackValue(callback: callbackNumber) {\n    this.callbackValue = callback;\n  }\n\n  private cloneRect(rect?: window.Rect): window.Rect {\n    return {\n      left: rect?.left ?? 0,\n      top: rect?.top ?? 0,\n      width: rect?.width ?? 0,\n      height: rect?.height ?? 0,\n    }\n  }\n\n  private cloneAvoidArea(avoidArea?: window.AvoidArea): window.AvoidArea {\n    return {\n      visible: avoidArea?.visible ?? false,\n      leftRect: this.cloneRect(avoidArea?.leftRect),\n      topRect: this.cloneRect(avoidArea?.topRect),\n      rightRect: this.cloneRect(avoidArea?.rightRect),\n      bottomRect: this.cloneRect(avoidArea?.bottomRect),\n    }\n  }\n\n",
    )
  }

  content = content.replace(
    '    this.systemAvoidArea = this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);\n',
    '    this.systemAvoidArea = this.cloneAvoidArea(this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM));\n',
  )
  content = content.replace(
    '    this.navigationAvoidArea = this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);\n',
    '    this.navigationAvoidArea = this.cloneAvoidArea(this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR));\n',
  )
  content = content.replace(
    '    this.gestureAvoidArea = this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);\n',
    '    this.gestureAvoidArea = this.cloneAvoidArea(this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE));\n',
  )
  content = content.replace(
    '    this.keyboardAvoidArea = this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);\n',
    '    this.keyboardAvoidArea = this.cloneAvoidArea(this.mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD));\n',
  )

  content = content.replace(
    "      case window.AvoidAreaType.TYPE_SYSTEM:\n        this.systemAvoidArea = data.area;\n        break;\n",
    "      case window.AvoidAreaType.TYPE_SYSTEM:\n        this.systemAvoidArea = this.cloneAvoidArea(data.area);\n        break;\n",
  )
  content = content.replace(
    "      case window.AvoidAreaType.TYPE_SYSTEM_GESTURE:\n        this.gestureAvoidArea = data.area;\n        break;\n",
    "      case window.AvoidAreaType.TYPE_SYSTEM_GESTURE:\n        this.gestureAvoidArea = this.cloneAvoidArea(data.area);\n        break;\n",
  )
  content = content.replace(
    "      case window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR:\n        this.navigationAvoidArea = data.area;\n        break;\n",
    "      case window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR:\n        this.navigationAvoidArea = this.cloneAvoidArea(data.area);\n        break;\n",
  )

  content = content.replace(
    "      case window.AvoidAreaType.TYPE_KEYBOARD:\n        if (this.getKeyboardHeight() > 0) {\n          this.keyboardAvoidArea = data.area;\n        } else {\n          this.keyboardAvoidArea.bottomRect = { left: 0, top: 0, width: 0, height: 0 };\n        }\n        break;\n",
    "      case window.AvoidAreaType.TYPE_KEYBOARD:\n        if (this.getKeyboardHeight() > 0) {\n          this.keyboardAvoidArea = this.cloneAvoidArea(data.area);\n        } else {\n          this.keyboardAvoidArea.bottomRect = { left: 0, top: 0, width: 0, height: 0 };\n        }\n        break;\n",
  )
  content = content.replace(
    "      case window.AvoidAreaType.TYPE_KEYBOARD:\n        this.keyboardAvoidArea = data.area;\n        this.keyboardHeight = data.area?.bottomRect?.height ?? 0;\n        break;\n",
    "      case window.AvoidAreaType.TYPE_KEYBOARD:\n        if (this.getKeyboardHeight() > 0) {\n          this.keyboardAvoidArea = this.cloneAvoidArea(data.area);\n        } else {\n          this.keyboardAvoidArea.bottomRect = { left: 0, top: 0, width: 0, height: 0 };\n        }\n        break;\n",
  )

  content = content.replace(
    "  private keyboardHeightChangeCallback = (data: number) => {\n    Log.i(TAG, \"keyboardHeightChangeCallback \" + data);\n    this.keyboardHeight = data;\n    this.onAreaChange(null);\n  };\n",
    "  private keyboardHeightChangeCallback = (data: number) => {\n    Log.i(TAG, \"keyboardHeightChangeCallback \" + data);\n    if (this.keyboardAvoidArea) {\n      this.keyboardAvoidArea.bottomRect.height = data;\n    }\n    this.onAreaChange(null);\n  };\n",
  )

  content = content.replace(
    "  getKeyboardHeight() {\n    return this.keyboardHeight\n  }\n",
    "  getKeyboardHeight() {\n    return this.keyboardAvoidArea?.bottomRect.height\n  }\n",
  )

  content = content.replace(
    "  private onKeyboardAreaChange(fullScreen: boolean = false) {\n    if (this.checkKeyboard && fullScreen && this.keyboardHeight > 0) {\n      this.viewportMetrics.physicalViewInsetTop =\n        this.keyboardAvoidArea?.topRect.height ?? 0\n      this.viewportMetrics.physicalViewInsetLeft =\n        this.keyboardAvoidArea?.leftRect.width ?? 0\n      this.viewportMetrics.physicalViewInsetBottom = this.keyboardHeight\n      this.viewportMetrics.physicalViewInsetRight =\n        this.keyboardAvoidArea?.rightRect.width ?? 0\n    } else {\n",
    "  private onKeyboardAreaChange(fullScreen: boolean = false) {\n    if (this.checkKeyboard && fullScreen) {\n      this.viewportMetrics.physicalViewInsetTop =\n        this.keyboardAvoidArea?.topRect.height ?? this.viewportMetrics.physicalViewInsetTop\n      this.viewportMetrics.physicalViewInsetLeft =\n        this.keyboardAvoidArea?.leftRect.width ?? this.viewportMetrics.physicalViewInsetLeft\n      this.viewportMetrics.physicalViewInsetBottom =\n        this.keyboardAvoidArea?.bottomRect.height ?? this.viewportMetrics.physicalViewInsetBottom\n      this.viewportMetrics.physicalViewInsetRight =\n        this.keyboardAvoidArea?.rightRect.width ?? this.viewportMetrics.physicalViewInsetRight\n    } else {\n",
  )

  if (
    !content.includes('  private cloneAvoidArea(avoidArea?: window.AvoidArea): window.AvoidArea {') ||
    !content.includes('this.keyboardAvoidArea = this.cloneAvoidArea') ||
    !content.includes('this.keyboardAvoidArea.bottomRect.height = data;') ||
    !content.includes('return this.keyboardAvoidArea?.bottomRect.height') ||
    content.includes('private keyboardHeight: number = 0;') ||
    content.includes('this.viewportMetrics.physicalViewInsetBottom = this.keyboardHeight') ||
    content.includes('this.keyboardHeight = this.keyboardAvoidArea?.bottomRect.height ?? 0;') ||
    content.includes('this.keyboardHeight = data;')
  ) {
    console.warn(`Skip incomplete flutter_ohos FlutterView avoid-area patch: ${flutterViewPath}`)
    return false
  }

  if (content === originalContent.replace(/\r\n/g, '\n')) {
    return false
  }

  fs.writeFileSync(flutterViewPath, content.replace(/\n/g, lineEnding), 'utf-8')
  console.info(`Patched flutter_ohos FlutterView avoid-area handling: ${flutterViewPath}`)
  return true
}

function getRepoOwnedHvigorPluginPath(flutterProjectPath: string): string {
  return path.join(flutterProjectPath, 'tooling', 'ohos-hvigor-plugin')
}

function shouldReinstallRepoOwnedHvigorPlugin(flutterProjectPath: string): boolean {
  const packageJsonPath = path.join(getOhosRoot(flutterProjectPath), 'package.json')
  if (!fs.existsSync(packageJsonPath)) {
    return true
  }

  try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'))
    if (packageJson.dependencies?.['flutter-hvigor-plugin'] !== REPO_OWNED_HVIGOR_PLUGIN_DEPENDENCY) {
      return true
    }
  } catch (error) {
    console.warn(`Failed to inspect OHOS package.json, reinstall repo-owned hvigor plugin by default. ${error}`)
    return true
  }

  const installedPluginPath = path.join(getOhosRoot(flutterProjectPath), 'node_modules', 'flutter-hvigor-plugin')
  if (!fs.existsSync(installedPluginPath)) {
    return true
  }

  try {
    const currentPluginPath = normalizeComparablePath(fs.realpathSync(installedPluginPath))
    const expectedPluginPath = normalizeComparablePath(getRepoOwnedHvigorPluginPath(flutterProjectPath))
    return currentPluginPath !== expectedPluginPath
  } catch (error) {
    console.warn(`Failed to inspect installed OHOS hvigor plugin path, reinstall by default. ${error}`)
    return true
  }
}

function ensureRepoOwnedHvigorPlugin(flutterProjectPath: string) {
  if (!shouldReinstallRepoOwnedHvigorPlugin(flutterProjectPath)) {
    return
  }

  const ohosRoot = getOhosRoot(flutterProjectPath)
  const packageJsonPath = path.join(ohosRoot, 'package.json')
  const packageJson = {
    dependencies: {
      'flutter-hvigor-plugin': REPO_OWNED_HVIGOR_PLUGIN_DEPENDENCY,
    },
  }

  fs.writeFileSync(
    packageJsonPath,
    `${JSON.stringify(packageJson, null, 2)}\n`,
    'utf-8',
  )

  const npmExecutableName = platform === 'win32' ? 'npm.cmd' : 'npm'
  console.info('Install repo-owned OHOS hvigor plugin start')
  execSync(
    `${npmExecutableName} install`,
    {
      cwd: ohosRoot,
      stdio: 'inherit',
      encoding: 'utf8',
    }
  )
  console.info('Install repo-owned OHOS hvigor plugin end')
}

export function flutterHvigorPlugin(flutterProjectPath: string, flutterProjectType: number = 0): HvigorPlugin {
  /**
   * 0: flutter app
   * 1: flutter module
   */
  return {
    pluginId: 'flutter-hvigor-plugin',
    apply(rootNode: HvigorNode) {
      const appContext = rootNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext
      const ohosDir = flutterProjectType === 1 ? '.ohos' : 'ohos'
      const flutterOhosStorePath = getFlutterOhosStorePath(flutterProjectPath)
      if (patchFlutterOhosFlutterViewAvoidAreaHandling(flutterProjectPath, flutterOhosStorePath)) {
        clearFlutterOhosArkTsBuildOutputs(flutterProjectPath)
      }
      const properties = loadProperties(path.join(flutterProjectPath, ohosDir, 'local.properties'))
      const flutterVersionInfo = getFlutterProjectVersionInfo(flutterProjectPath)
      const sdkPath = properties['flutter.sdk']
      const productName = appContext.getCurrentProduct().getProductName()
      const targetPlatforms = getParameters(TARGET_PLATFORM, DEFAULT_PLATFORMS)
      const buildMode = appContext.getBuildMode()
      rootNode.afterNodeEvaluate(node => {
        // app.json5
        if (flutterProjectType === 0) {
          const appJsonOpt = appContext.getAppJsonOpt()
          appJsonOpt['app']['versionCode'] = Number(
            flutterVersionInfo.versionCode ?? properties['flutter.versionCode'] ?? 1
          )
          appJsonOpt['app']['versionName'] =
            flutterVersionInfo.versionName ?? properties['flutter.versionName'] ?? '1.0'
          appContext.setAppJsonOpt(appJsonOpt)
        }
        // build-profile.json5
        const overrides = appContext.getOverrides() ?? {}
        setFlutterHarInOverrides(overrides, targetPlatforms!, sdkPath, buildMode)
        const nativePlugins = getNativePlugins(flutterProjectPath)
        nativePlugins.forEach(nativePlugin => {
          overrides[nativePlugin.name] =
            `file:${path.join(nativePlugin.path, 'ohos')}`
        })
        if (flutterProjectType == 1) {
          overrides['@ohos/flutter_module'] = `file:${path.join(flutterProjectPath, '.ohos', 'flutter_module')}`
        }
        appContext.setOverrides(overrides)
      })
      rootNode.subNodes(subNode => {
        // 浠呭綋entry鐨刪vigorfile.ts鏄互涓嬪舰寮忥細
        // export default {
        //   system: hapTasks,
        //   plugins: []
        // }
        // 浠ヤ笅淇敼鏂瑰彲鐢熸晥
        const subNodeName = subNode.getNodeName()
        if (subNodeName === 'entry') {
          subNode.afterNodeEvaluate(node => {
            const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext
            if (!hapContext) {
              return
            }
            if (flutterProjectType == 0) {
              hapContext.targets((target: Target) => {
                registerFlutterTask(node, sdkPath, buildMode, flutterProjectPath, target)
              })
            }
            const dependenciesOpt = hapContext.getDependenciesOpt()
            setFlutterHarInDependencies(dependenciesOpt, targetPlatforms)
            const nativePlugins = getNativePlugins(flutterProjectPath)
            nativePlugins.forEach(nativePlugin => {
              dependenciesOpt[nativePlugin.name] = ''
            })
            hapContext.setDependenciesOpt(dependenciesOpt)
          })
        } else if (subNodeName === 'flutter_module' && flutterProjectType === 1) {
          subNode.afterNodeEvaluate(node => {
            const harContext = node.getContext(OhosPluginId.OHOS_HAR_PLUGIN) as OhosHarContext
            if (!harContext) {
              return
            }
            harContext.targets((target: Target) => {
              registerFlutterTask(node, sdkPath, buildMode, flutterProjectPath, target)
            })
            const dependenciesOpt = harContext.getDependenciesOpt()
            setFlutterHarInDependencies(dependenciesOpt, targetPlatforms)
            const nativePlugins = getNativePlugins(flutterProjectPath)
            nativePlugins.forEach(nativePlugin => {
              dependenciesOpt[nativePlugin.name] = ''
            })
            harContext.setDependenciesOpt(dependenciesOpt)
          })
        } else if (getNativePlugins(flutterProjectPath).map(it => it.name).includes(subNodeName)) {
          // 浠呭綋flutter plugin鐨刪vigorfile.ts鏄互涓嬪舰寮忥細
          // export default {
          //   system: harTasks,
          //   plugins: []
          // }
          // 浠ヤ笅淇敼鏂瑰彲鐢熸晥
          subNode.afterNodeEvaluate(node => {
            const harContext = node.getContext(OhosPluginId.OHOS_HAR_PLUGIN) as OhosHarContext
            if (!harContext) {
              return
            }
            const dependenciesOpt = harContext.getDependenciesOpt()
            setFlutterHarInDependencies(dependenciesOpt, targetPlatforms)
            harContext.setDependenciesOpt(dependenciesOpt)
          })
        }
      })
    }
  }
}

function setFlutterHarInDependencies(dependenciesOpt: any, targetPlatforms: string[] | undefined) {
  dependenciesOpt['@ohos/flutter_ohos'] = ''
  targetPlatforms?.map(platform => PLATFORM_ARCH_MAP[platform].replace('-', '_'))
    .forEach(arch => {
      dependenciesOpt[`flutter_native_${arch}`] = ''
    })
}

function setFlutterHarInOverrides(
  overrides: Record<string, string>,
  targetPlatforms: string[],
  sdkPath: string,
  buildMode: string) {
  const buildModeSuffix = buildMode !== 'debug' ? `-${buildMode}` : ''
  targetPlatforms?.forEach((platform, index: number) => {
    const arch = PLATFORM_ARCH_MAP[platform].replace('-', '_')
    const cacheDir = localEngineSrcPath && localEngine
      ? path.join(localEngineSrcPath, "out", localEngine)
      : path.join(sdkPath, 'bin', 'cache', 'artifacts', 'engine', `${platform}${buildModeSuffix}`)

    if (index == 0) {
      // Set flutter_embedding_${buildMode} override for the first target platform
      const flutterHarPath = path.join(cacheDir, `flutter_embedding_${buildMode}.har`)
      overrides['@ohos/flutter_ohos'] = `file:${realFilePath(flutterHarPath)}`
    }
    // Set flutter_native_${arch} overrides for each target platform
    const platformHarPath = path.join(cacheDir, `${arch}_${buildMode}.har`)
    overrides[`flutter_native_${arch}`] = `file:${realFilePath(platformHarPath)}`
  })
}

export function injectNativeModules(nativeProjectPath: string, flutterProjectPath: string,
  flutterProjectType: number = 0) {
  /**
   * 0: flutter app
   * 1: flutter module
   */
  const hvigorConfig = hvigor.getHvigorConfig()
  if (flutterProjectType === 1) {
    const srcPath = relativePath(nativeProjectPath, path.join(flutterProjectPath, '.ohos', 'flutter_module'))
    hvigorConfig.includeNode(
      'flutter_module',
      srcPath
    )
  }
  getNativePlugins(flutterProjectPath).forEach(nativePlugin => {
    const srcPath = relativePath(nativeProjectPath, path.join(nativePlugin.path, 'ohos'))
    hvigorConfig.includeNode(
      nativePlugin.name,
      srcPath
    )
  })
}

// sync function
function copyConfigsFile(srcDir: string, destDir: string) {
  console.info("copy ConfigsFile start")

  if (!fs.existsSync(srcDir)) {
    console.error(srcDir + " not exists, failed to copy ConfigsFile")
    return
  }

  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(path.dirname(destDir), {recursive: true})
  }

  // buildinfo.json5
  const srcBuildInfoFile = path.join(
    srcDir,
    "buildinfo.json5"
  )
  const destBuildInfoFile = path.join(
    destDir,
    "buildinfo.json5"
  )
  if (fs.existsSync(srcBuildInfoFile)) {
    if (!fs.existsSync(destBuildInfoFile)) {
      fs.copyFileSync(srcBuildInfoFile, destBuildInfoFile)
    }
    fs.unlinkSync(srcBuildInfoFile)
  } else {
    console.info("buildinfo.json5 not exist")
  }

  // framesconfig.json
  const srcFramesConfigFile = path.join(
    srcDir,
    "framesconfig.json"
  )
  const destFramesConfigFile = path.join(
    destDir,
    "framesconfig.json"
  )
  if (fs.existsSync(srcFramesConfigFile)) {
    if (!fs.existsSync(destFramesConfigFile)) {
      fs.copyFileSync(srcFramesConfigFile, destFramesConfigFile)
    }
    fs.unlinkSync(srcFramesConfigFile)
  } else {
    console.info("framesconfig.json not exist")
  }

  console.info("copy ConfigsFile end")
}

function registerFlutterTask(node: HvigorNode, sdkPath: string, buildMode: string, flutterProjectPath: string,
  target: Target) {
  const targetPlatforms = getParameters(TARGET_PLATFORM, DEFAULT_PLATFORMS)
  const productName = target.getCurrentProduct().getProductName()
  const targetName = target.getTargetName()
  // const outputPath = target.getBuildTargetOutputPath()
  node.registerTask({
    name: `${targetName}@FlutterTask`,
    postDependencies: [`${targetName}@MergeProfile`],
    run: (taskContext) => {
      // flutter assemble
      const flutterExecutableName = platform === 'win32' ? 'flutter.bat' : 'flutter'
      const flutterExecutablePath = path.join(
        sdkPath,
        'bin',
        flutterExecutableName
      )
      const sessionStateBackupRoot = switchToOhosFlutterState(
        flutterExecutablePath,
        flutterProjectPath,
        sdkPath,
      )
      const flutterOhosStorePath = getFlutterOhosStorePath(flutterProjectPath)
      if (patchFlutterOhosFlutterViewAvoidAreaHandling(flutterProjectPath, flutterOhosStorePath)) {
        clearFlutterOhosArkTsBuildOutputs(flutterProjectPath)
      }
      clearStaleFlutterOhosArkTsCache(flutterProjectPath, flutterOhosStorePath)
      try {
        let targetNames: string[]
        if (buildMode === 'debug') {
          targetNames = ['debug_ohos_application']
        } else if (buildMode === 'profile') {
          targetNames = targetPlatforms.map(it => `ohos_aot_bundle_profile_${it}`)
        } else {
          targetNames = targetPlatforms.map(it => `ohos_aot_bundle_release_${it}`)
        }
        const flutterArgs: string[] = []
        flutterArgs.push(flutterExecutablePath)
        if (localEngineSrcPath) {
          flutterArgs.push('--local-engine-src-path', localEngineSrcPath)
        }
        if (localEngine) {
          flutterArgs.push('--local-engine', localEngine)
        }
        if (localEngineHost) {
          flutterArgs.push('--local-engine-host', localEngineHost)
        }
        if (getParameter('VERBOSE_SCRIPT_LOGGING') === 'true') {
          flutterArgs.push('--verbose')
        } else {
          flutterArgs.push('--quiet')
        }
        flutterArgs.push('assemble')
        flutterArgs.push('--no-version-check')
        const intermediateDir = `build/ohos/intermediates/flutter/${toCamelCase([productName, buildMode])}`
        flutterArgs.push('--depfile', `${intermediateDir}/flutter_build.d`)
        flutterArgs.push('--output', `${intermediateDir}`)
        const performanceMeasurementFile = getParameter('PERFORMANCE_MEASUREMENT_FILE')
        if (performanceMeasurementFile) {
          flutterArgs.push(`--performance-measurement-file=${performanceMeasurementFile}`)
        }
        const targetPath = getParameter('FLUTTER_TARGET', 'lib/main.dart')
        flutterArgs.push(`-dTargetFile=${targetPath}`)
        flutterArgs.push('-dTargetPlatform=ohos')
        flutterArgs.push(`-dBuildMode=${buildMode}`)
        const trackWidgetCreation = getParameter('TRACK_WIDGET_CREATION')
        if (trackWidgetCreation) {
          flutterArgs.push(`-dTrackWidgetCreation=${trackWidgetCreation}`)
        }
        const splitDebugInfo = getParameter('SPLIT_DEBUG_INFO')
        if (splitDebugInfo) {
          flutterArgs.push(`-dSplitDebugInfo=${splitDebugInfo}`)
        }
        const treeShakeIcons = getParameter('TREE_SHAKE_ICONS')
        if (treeShakeIcons === 'true') {
          flutterArgs.push('-dTreeShakeIcons=true')
        }
        const dartObfuscation = getParameter('DART_OBFUSCATION')
        if (dartObfuscation === 'true') {
          flutterArgs.push('-dDartObfuscation=true')
        }
        const dartDefines = getParameter('DART_DEFINES')
        if (dartDefines) {
          flutterArgs.push(`--DartDefines=${dartDefines}`)
        }
        const bundleSkSLPath = getParameter('BUNDLE_SKSL_PATH')
        if (bundleSkSLPath) {
          flutterArgs.push(`-dBundleSkSLPath=${bundleSkSLPath}`)
        }
        const codeSizeDirectory = getParameter('CODE_SIZE_DIRECTORY')
        if (codeSizeDirectory) {
          flutterArgs.push(`-dCodeSizeDirectory=${codeSizeDirectory}`)
        }
        if (productName !== 'default') {
          flutterArgs.push(`-dFlavor=${productName}`)
        }
        const extraGenSnapshotOptions = getParameter('EXTRA_GEN_SNAPSHOT_OPTIONS')
        if (extraGenSnapshotOptions) {
          flutterArgs.push(`--ExtraGenSnapshotOptions=${extraGenSnapshotOptions}`)
        }
        const frontendServerStarterPath = getParameter('FRONTEND_SERVER_STARTER_PATH')
        if (frontendServerStarterPath) {
          flutterArgs.push(`-dFrontendServerStarterPath=${frontendServerStarterPath}`)
        }
        const extraFrontEndOptions = getParameter('EXTRA_FRONT_END_OPTIONS')
        if (extraFrontEndOptions) {
          flutterArgs.push(`--ExtraFrontEndOptions=${extraFrontEndOptions}`)
        }
        flutterArgs.push(`-dOhosArchs=${targetPlatforms.join(' ')}`)
        flutterArgs.push(...targetNames)
        const command = flutterArgs.join(' ')
        try {
          const result = execSync(
            command,
            {
              cwd: flutterProjectPath,
              encoding: 'utf8',
            }
          ).toString()
          console.log(`flutter assemble: ${result}`)
        } catch (error) {
          console.error(`flutter assemble: ${error.message}`)
        }
        // copy flutter assets && app.so
        console.log('copy flutter assets to project start')
        // 1.clean flutter assets
        const nodePath = node.getNodePath()
        const destFlutterAssetsDir = path.join(
          nodePath,
          'src',
          'main',
          'resources',
          'rawfile',
          FLUTTER_ASSETS_PATH
        )
        if (fs.existsSync(destFlutterAssetsDir)) {
          fs.rmSync(destFlutterAssetsDir, { recursive: true })
        }
        // 2.copy flutter assets
        const srcFlutterAssetsDir = path.join(
          flutterProjectPath,
          intermediateDir,
          FLUTTER_ASSETS_PATH
        )
        copyDirectory(srcFlutterAssetsDir, destFlutterAssetsDir)
        // 3.copy app.so
        const libsDir = path.join(nodePath, 'libs')
        if (fs.existsSync(libsDir)) {
          const files = listFiles(libsDir)
          for (const file of files) {
            if (path.basename(file) === 'libapp.so') {
              fs.unlinkSync(file)
            }
          }
        }
        if (buildMode !== 'debug') {
          targetPlatforms?.map(platform => PLATFORM_ARCH_MAP[platform]).forEach(arch => {
            const destAppSoPath = path.join(
              nodePath,
              'libs',
              arch,
              'libapp.so'
            )
            const srcAppSoPath = path.join(
              flutterProjectPath,
              intermediateDir,
              arch,
              'app.so'
            )
            if (!fs.existsSync(path.dirname(destAppSoPath))) {
              fs.mkdirSync(path.dirname(destAppSoPath), { recursive: true })
            }
            fs.copyFileSync(srcAppSoPath, destAppSoPath)
          })
        }
        console.log('copy flutter assets to project end')

        // 4.Copy configuration files in 'profile' to 'rawfile',
        // such as buildinfo.json5 and framesconfig.json
        // srcDir: ohos/entry/src/main/resources/base/profile/
        // destDir: ohos/entry/src/main/resources/rawfile/
        const srcFlutterConfigsDir = path.join(
          nodePath,
          "src",
          "main",
          "resources",
          "base",
          "profile"
        )

        const destFlutterConfigsDir = path.join(
          nodePath,
          "src",
          "main",
          "resources",
          "rawfile"
        )

        copyConfigsFile(srcFlutterConfigsDir, destFlutterConfigsDir)
      } finally {
        restoreFlutterSharedState(flutterProjectPath, sessionStateBackupRoot)
      }
    },
  })
}

function findFlutterPlugins(flutterPluginsDependenciesPath: string): JSON[] {
  if (!fs.existsSync(flutterPluginsDependenciesPath)) {
    return []
  }
  const fileContent = fs.readFileSync(flutterPluginsDependenciesPath, 'utf-8')
  const pluginsByPlatform = JSON.parse(fileContent).plugins ?? {}
  const ohosPlugins = Array.isArray(pluginsByPlatform.ohos)
    ? pluginsByPlatform.ohos
    : []
  return ohosPlugins.filter(plugin => plugin.native_build !== false)
}

function getNativePlugins(flutterProjectPath: string): JSON[] {
  return findFlutterPlugins(getFlutterPluginsDependenciesPath(flutterProjectPath))
}
