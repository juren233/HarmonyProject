param(
  [ValidateSet('test', 'build', 'install', 'run')]
  [string]$Mode = 'build',
  [ValidateSet('x64', 'arm64', 'arm')]
  [string]$TargetPlatform = 'x64',
  [string]$DeviceId = '127.0.0.1:5555'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'flutter-state.ps1')

function Resolve-ExistingPath {
  param(
    [string[]]$Candidates,
    [string]$Label
  )

  foreach ($candidate in $Candidates) {
    if (-not $candidate) {
      continue
    }

    if (Test-Path $candidate) {
      return (Resolve-Path $candidate).Path
    }

    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  throw "$Label was not found."
}

function Invoke-Checked {
  param(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$Workdir
  )

  if ($Workdir) {
    Push-Location $Workdir
  }

  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    if ($Workdir) {
      Pop-Location
    }
    throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
  }

  if ($Workdir) {
    Pop-Location
  }
}

function Ensure-OhosFlutterSubmodule {
  param(
    [string]$RepoRoot,
    [string]$SubmodulePath
  )

  if (Test-Path (Join-Path $SubmodulePath 'bin\flutter.bat')) {
    return
  }

  $git = Resolve-ExistingPath -Candidates @('git.exe', 'git') -Label 'git'
  Invoke-Checked -Executable $git -Arguments @('-C', $RepoRoot, 'submodule', 'update', '--init', '--recursive', '.flutter_ohos_sdk_gitcode')
}

function Ensure-HvigorPluginPatched {
  param(
    [string]$FilePath
  )

  if (-not (Test-Path $FilePath)) {
    return
  }

  $content = (Get-Content -Path $FilePath -Raw).Replace("`r`n", "`n")

  $refreshStartMarker = "console.info('Refresh Flutter package config for OHOS IDE run start')"
  $backupStateMarker = "console.info('Backup Flutter shared state start')"
  $pluginGuardMarker = 'const pluginsByPlatform = JSON.parse(fileContent).plugins ?? {}'

  $stateHelpersSnippet = @'
const MANAGED_FLUTTER_STATE_FILES = [
  'pubspec.lock',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.dart_tool/package_config.json',
  '.dart_tool/package_config_subset',
  '.dart_tool/package_graph.json',
  '.dart_tool/version',
  'android/local.properties',
  'ohos/local.properties',
]

function ensureParentDirectory(targetPath: string) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true })
}

function removePathIfExists(targetPath: string) {
  if (fs.existsSync(targetPath)) {
    fs.rmSync(targetPath, { recursive: true, force: true })
  }
}

function copyFilePreservingParent(sourcePath: string, destinationPath: string) {
  ensureParentDirectory(destinationPath)
  fs.copyFileSync(sourcePath, destinationPath)
}

function getFlutterStateRoot(flutterProjectPath: string, stateName: string): string {
  return path.join(flutterProjectPath, '.tooling', 'flutter-state', stateName)
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
'@

  $packageHelpersSnippet = @'
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

function shouldRefreshFlutterPackages(flutterProjectPath: string, sdkPath: string): boolean {
  const packageConfigPath = path.join(flutterProjectPath, '.dart_tool', 'package_config.json')
  if (!fs.existsSync(packageConfigPath)) {
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
'@

  if (-not $content.Contains($backupStateMarker)) {
    $normalizeMarker = 'function normalizeComparablePath(filePath: string): string {'
    $normalizeIndex = $content.IndexOf($normalizeMarker)
    if ($normalizeIndex -lt 0) {
      Write-Warning "Skip OHOS IDE shared-state backup patch because normalizeComparablePath was not found in $FilePath"
    }
    else {
      $content = $content.Insert($normalizeIndex, "$stateHelpersSnippet`n")
    }
  }

  if (-not $content.Contains($refreshStartMarker)) {
    $registerTaskAnchor = 'function registerFlutterTask(node: HvigorNode, sdkPath: string, buildMode: string, flutterProjectPath: string,'
    $registerTaskIndex = $content.IndexOf($registerTaskAnchor)
    if ($registerTaskIndex -lt 0) {
      Write-Warning "Skip OHOS IDE package-config auto-refresh patch because registerFlutterTask was not found in $FilePath"
    }
    else {
      $content = $content.Insert($registerTaskIndex, "$packageHelpersSnippet`n")
    }
  }

  if (-not $content.Contains('ensureFlutterPackages(flutterExecutablePath, flutterProjectPath, sdkPath)')) {
    $oldRegisterSnippet = @'
      const flutterExecutablePath = path.join(
        sdkPath,
        'bin',
        flutterExecutableName
      )
      let targetNames: string[]
'@

    $newRegisterSnippet = @'
      const flutterExecutablePath = path.join(
        sdkPath,
        'bin',
        flutterExecutableName
      )
      ensureFlutterPackages(flutterExecutablePath, flutterProjectPath, sdkPath)
      let targetNames: string[]
'@

    if (-not $content.Contains($oldRegisterSnippet)) {
      Write-Warning "Skip OHOS IDE package-config auto-refresh hook because flutterExecutablePath block was not matched in $FilePath"
    }
    else {
      $content = $content.Replace($oldRegisterSnippet, $newRegisterSnippet)
    }
  }

  if (-not $content.Contains('const sessionStateBackupRoot = switchToOhosFlutterState(')) {
    $oldSwitchSnippet = @'
      ensureFlutterPackages(flutterExecutablePath, flutterProjectPath, sdkPath)
      let targetNames: string[]
'@

    $newSwitchSnippet = @'
      const sessionStateBackupRoot = switchToOhosFlutterState(
        flutterExecutablePath,
        flutterProjectPath,
        sdkPath,
      )
      try {
        let targetNames: string[]
'@

    if (-not $content.Contains($oldSwitchSnippet)) {
      Write-Warning "Skip OHOS IDE shared-state switch hook because ensureFlutterPackages block was not matched in $FilePath"
    }
    else {
      $content = $content.Replace($oldSwitchSnippet, $newSwitchSnippet)
    }
  }

  if (-not $content.Contains('restoreFlutterSharedState(flutterProjectPath, sessionStateBackupRoot)')) {
    $oldRestoreSnippet = @'
        copyConfigsFile(srcFlutterConfigsDir, destFlutterConfigsDir)

    },
'@

    $newRestoreSnippet = @'
        copyConfigsFile(srcFlutterConfigsDir, destFlutterConfigsDir)
      } finally {
        restoreFlutterSharedState(flutterProjectPath, sessionStateBackupRoot)
      }

    },
'@

    if (-not $content.Contains($oldRestoreSnippet)) {
      Write-Warning "Skip OHOS IDE shared-state restore hook because copyConfigsFile block was not matched in $FilePath"
    }
    else {
      $content = $content.Replace($oldRestoreSnippet, $newRestoreSnippet)
    }
  }

  if (-not $content.Contains($pluginGuardMarker)) {
    $oldPluginSnippet = @'
  const ohosPlugins = JSON.parse(fileContent).plugins.ohos
  const filteredPlugins =
    ohosPlugins.filter(plugin => plugin.native_build !== false)
  return filteredPlugins
'@

    $newPluginSnippet = @'
  const pluginsByPlatform = JSON.parse(fileContent).plugins ?? {}
  const ohosPlugins = Array.isArray(pluginsByPlatform.ohos)
    ? pluginsByPlatform.ohos
    : []
  return ohosPlugins.filter(plugin => plugin.native_build !== false)
'@

    if (-not $content.Contains($oldPluginSnippet)) {
      throw "Unsupported flutter-hvigor-plugin content in $FilePath"
    }

    $content = $content.Replace($oldPluginSnippet, $newPluginSnippet)
  }

  Set-Content -Path $FilePath -Value ($content.Replace("`n", "`r`n")) -Encoding utf8
}

function Ensure-RepoOwnedHvigorPluginDependency {
  param(
    [string]$RepoRoot
  )

  $ohosRoot = Join-Path $RepoRoot 'ohos'
  $packageJsonPath = Join-Path $ohosRoot 'package.json'
  $packageLockPath = Join-Path $ohosRoot 'package-lock.json'
  $expectedDependency = 'file:../tooling/ohos-hvigor-plugin'
  $expectedResolvedPath = (Resolve-Path (Join-Path $RepoRoot 'tooling\\ohos-hvigor-plugin')).Path
  $currentResolvedPath = $null

  if (Test-Path (Join-Path $ohosRoot 'node_modules\\flutter-hvigor-plugin')) {
    try {
      $currentResolvedPath = (Resolve-Path (Join-Path $ohosRoot 'node_modules\\flutter-hvigor-plugin')).Path
    }
    catch {
      $currentResolvedPath = $null
    }
  }

  $needsInstall = $true
  if ((Test-Path $packageJsonPath) -and (Test-Path $packageLockPath) -and $currentResolvedPath) {
    $packageJsonContent = Get-Content $packageJsonPath -Raw
    $packageLockContent = Get-Content $packageLockPath -Raw
    if (
      $packageJsonContent.Contains('"flutter-hvigor-plugin": "' + $expectedDependency + '"') -and
      $packageLockContent.Contains('"flutter-hvigor-plugin": "' + $expectedDependency + '"') -and
      $packageLockContent.Contains('"resolved": "../tooling/ohos-hvigor-plugin"') -and
      ($currentResolvedPath -eq $expectedResolvedPath)
    ) {
      $needsInstall = $false
    }
  }

  if (-not $needsInstall) {
    return
  }

  $packageJson = @{
    dependencies = @{
      'flutter-hvigor-plugin' = $expectedDependency
    }
  } | ConvertTo-Json -Depth 5

  Set-Content -Path $packageJsonPath -Value $packageJson -Encoding utf8

  $npm = Resolve-ExistingPath -Candidates @('npm.cmd', 'npm') -Label 'npm'
  Invoke-Checked -Executable $npm -Arguments @('install') -Workdir $ohosRoot
}

function Invoke-AllowingUnsignedBuild {
  param(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$UnsignedHapPath
  )

  & $Executable @Arguments
  if ($LASTEXITCODE -eq 0) {
    return
  }

  if (Test-Path $UnsignedHapPath) {
    Write-Host 'Flutter build stopped at signing config validation, but the unsigned HAP was produced. Continuing with manual signing.'
    return
  }

  throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
}

function Export-Certificate {
  param(
    [string]$Keytool,
    [string]$KeystoreFile,
    [string]$StorePassword,
    [string]$Alias,
    [string]$OutFile
  )

  $content = & $Keytool -exportcert -rfc -keystore $KeystoreFile -storetype PKCS12 -storepass $StorePassword -alias $Alias
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to export certificate alias: $Alias"
  }
  $content | Set-Content -Path $OutFile -Encoding ascii
}

function Get-DeviceUdid {
  param(
    [string]$Hdc,
    [string]$Target
  )

  $output = & $Hdc -t $Target shell bm get --udid
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to query device UDID for $Target"
  }

  $match = $output | Select-String '([A-F0-9]{64})' | Select-Object -First 1
  $udid = $null
  if ($match -and $match.Matches.Count -gt 0) {
    $udid = $match.Matches[0].Value
  }
  if (-not $udid) {
    throw "Could not parse a device UDID from: $output"
  }

  return $udid
}

function New-DebugProfileJson {
  param(
    [string]$TemplatePath,
    [string]$BundleName,
    [string]$DeviceUdid,
    [string]$OutFile
  )

  $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $template.'version-name' = '1.0.0'
  $template.'version-code' = 1
  $template.uuid = [guid]::NewGuid().ToString()
  $template.validity.'not-before' = $now
  $template.validity.'not-after' = $now + 315360000
  $template.'bundle-info'.'bundle-name' = $BundleName
  $template.'debug-info'.'device-ids' = @($DeviceUdid)
  $template | ConvertTo-Json -Depth 10 | Set-Content -Path $OutFile -Encoding utf8
}

function Get-CompatibleApiVersion {
  param(
    [string]$PackInfoPath
  )

  $packInfo = Get-Content $PackInfoPath -Raw | ConvertFrom-Json
  return [string]$packInfo.summary.modules[0].apiVersion.compatible
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sdkRepoRoot = Join-Path $repoRoot '.flutter_ohos_sdk_gitcode'
Ensure-OhosFlutterSubmodule -RepoRoot $repoRoot -SubmodulePath $sdkRepoRoot
$flutterSdk = Resolve-ExistingPath -Candidates @(
  (Join-Path $sdkRepoRoot 'bin\flutter.bat')
) -Label 'Flutter OH SDK'
$devEcoSdkHome = Resolve-ExistingPath -Candidates @(
  $env:DEVECO_SDK_HOME,
  'E:\Huawei\DevEco Studio\sdk'
) -Label 'DevEco SDK'
$ohToolchainDir = Resolve-ExistingPath -Candidates @(
  (Join-Path $devEcoSdkHome 'default\openharmony\toolchains')
) -Label 'OpenHarmony toolchains'
$hapSignTool = Resolve-ExistingPath -Candidates @(
  (Join-Path $ohToolchainDir 'lib\hap-sign-tool.jar')
) -Label 'hap-sign-tool'
$keystoreFile = Resolve-ExistingPath -Candidates @(
  (Join-Path $ohToolchainDir 'lib\OpenHarmony.p12')
) -Label 'OpenHarmony.p12'
$profileCertChain = Resolve-ExistingPath -Candidates @(
  (Join-Path $ohToolchainDir 'lib\OpenHarmonyProfileDebug.pem')
) -Label 'OpenHarmonyProfileDebug.pem'
$profileTemplate = Resolve-ExistingPath -Candidates @(
  (Join-Path $ohToolchainDir 'lib\UnsgnedDebugProfileTemplate.json')
) -Label 'UnsgnedDebugProfileTemplate.json'

$env:DEVECO_SDK_HOME = $devEcoSdkHome
$env:PUB_CACHE = (Join-Path (Split-Path $repoRoot -Parent) 'pub_cache')
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:FLUTTER_GIT_URL = 'https://gitcode.com/openharmony-tpc/flutter_flutter.git'
$env:Path = @(
  (Split-Path $flutterSdk -Parent),
  'E:\Huawei\DevEco Studio\tools\ohpm\bin',
  'E:\Huawei\DevEco Studio\tools\hvigor\bin',
  'E:\Huawei\DevEco Studio\tools\node',
  $ohToolchainDir,
  $env:Path
) -join ';'

$signingDir = Join-Path $repoRoot '.signing-temp'
$unsignedHap = Join-Path $repoRoot 'ohos\entry\build\default\outputs\default\entry-default-unsigned.hap'
$signedHap = Join-Path $repoRoot 'ohos\entry\build\default\outputs\default\entry-default-signed.hap'
$builtSignedHap = Join-Path $repoRoot 'build\ohos\hap\entry-default-signed.hap'
$packInfo = Join-Path $repoRoot 'ohos\entry\build\default\outputs\default\pack.info'
$bundleInfo = Get-Content (Join-Path $repoRoot 'ohos\AppScope\app.json5') -Raw | ConvertFrom-Json
$bundleName = [string]$bundleInfo.app.bundleName
$abilityName = 'EntryAbility'
$keystorePassword = '123456'

Push-Location $repoRoot
$stateBackup = Backup-ManagedState -RepoRoot $repoRoot
try {
  Ensure-HvigorPluginPatched -FilePath (Join-Path $repoRoot 'tooling\ohos-hvigor-plugin\src\plugin\flutter-hvigor-plugin.ts')

  Restore-PlatformState -RepoRoot $repoRoot -StateName 'ohos' | Out-Null

  if ($Mode -eq 'test') {
    Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
    Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot
    Save-PlatformState -RepoRoot $repoRoot -StateName 'ohos'
    Invoke-Checked -Executable $flutterSdk -Arguments @('test')
    Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot
    return
  }

  Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
  Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot
  Save-PlatformState -RepoRoot $repoRoot -StateName 'ohos'

  $keytool = Resolve-ExistingPath -Candidates @('keytool.exe', 'keytool') -Label 'keytool'
  $hdc = Resolve-ExistingPath -Candidates @(
    (Join-Path $ohToolchainDir 'hdc.exe'),
    'hdc.exe',
    'hdc'
  ) -Label 'hdc'

  New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

  Invoke-AllowingUnsignedBuild `
    -Executable $flutterSdk `
    -Arguments @('build', 'hap', '--debug', '--target-platform', "ohos-$TargetPlatform", '--no-tree-shake-icons') `
    -UnsignedHapPath $unsignedHap
  Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot

  $resolvedSignedHap = @($builtSignedHap, $signedHap) |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

  if ($resolvedSignedHap) {
    if ($Mode -eq 'install' -or $Mode -eq 'run') {
      Invoke-Checked -Executable $hdc -Arguments @('-t', $DeviceId, 'install', '-r', $resolvedSignedHap)
    }

    if ($Mode -eq 'run') {
      Invoke-Checked -Executable $hdc -Arguments @('-t', $DeviceId, 'shell', 'aa', 'start', '-b', $bundleName, '-a', $abilityName)
    }

    return
  }

  if (-not (Test-Path $unsignedHap)) {
    throw "Unsigned HAP was not generated at $unsignedHap"
  }

  $deviceUdid = Get-DeviceUdid -Hdc $hdc -Target $DeviceId

  $rootCaFile = Join-Path $signingDir 'root-ca.cer'
  $appCaFile = Join-Path $signingDir 'app-ca.cer'
  $profileJson = Join-Path $signingDir 'profile-debug.json'
  $signedProfile = Join-Path $signingDir 'signed-profile.p7b'
  $appCertChain = Join-Path $signingDir 'app-release-chain-generated.cer'

  Export-Certificate -Keytool $keytool -KeystoreFile $keystoreFile -StorePassword $keystorePassword -Alias 'openharmony application root ca' -OutFile $rootCaFile
  Export-Certificate -Keytool $keytool -KeystoreFile $keystoreFile -StorePassword $keystorePassword -Alias 'openharmony application ca' -OutFile $appCaFile
  New-DebugProfileJson -TemplatePath $profileTemplate -BundleName $bundleName -DeviceUdid $deviceUdid -OutFile $profileJson

  Invoke-Checked -Executable 'java' -Arguments @(
    '-jar', $hapSignTool,
    'generate-app-cert',
    '-keyAlias', 'openharmony application release',
    '-keyPwd', $keystorePassword,
    '-issuer', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA',
    '-issuerKeyAlias', 'openharmony application ca',
    '-issuerKeyPwd', $keystorePassword,
    '-subject', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release',
    '-validity', '3650',
    '-signAlg', 'SHA256withECDSA',
    '-rootCaCertFile', $rootCaFile,
    '-subCaCertFile', $appCaFile,
    '-keystoreFile', $keystoreFile,
    '-keystorePwd', $keystorePassword,
    '-outForm', 'certChain',
    '-outFile', $appCertChain
  )

  Invoke-Checked -Executable 'java' -Arguments @(
    '-jar', $hapSignTool,
    'sign-profile',
    '-mode', 'localSign',
    '-keyAlias', 'openharmony application profile debug',
    '-keyPwd', $keystorePassword,
    '-profileCertFile', $profileCertChain,
    '-inFile', $profileJson,
    '-signAlg', 'SHA256withECDSA',
    '-keystoreFile', $keystoreFile,
    '-keystorePwd', $keystorePassword,
    '-outFile', $signedProfile
  )

  $compatibleVersion = Get-CompatibleApiVersion -PackInfoPath $packInfo
  Invoke-Checked -Executable 'java' -Arguments @(
    '-jar', $hapSignTool,
    'sign-app',
    '-mode', 'localSign',
    '-keyAlias', 'openharmony application release',
    '-keyPwd', $keystorePassword,
    '-appCertFile', $appCertChain,
    '-profileFile', $signedProfile,
    '-inFile', $unsignedHap,
    '-signAlg', 'SHA256withECDSA',
    '-keystoreFile', $keystoreFile,
    '-keystorePwd', $keystorePassword,
    '-outFile', $signedHap,
    '-compatibleVersion', $compatibleVersion,
    '-signCode', '1'
  )

  if ($Mode -eq 'install' -or $Mode -eq 'run') {
    Invoke-Checked -Executable $hdc -Arguments @('-t', $DeviceId, 'install', '-r', $signedHap)
  }

  if ($Mode -eq 'run') {
    Invoke-Checked -Executable $hdc -Arguments @('-t', $DeviceId, 'shell', 'aa', 'start', '-b', $bundleName, '-a', $abilityName)
  }
}
finally {
  $restoredOfficialState = Restore-PlatformState -RepoRoot $repoRoot -StateName 'official'
  if (-not $restoredOfficialState) {
    Restore-ManagedStateFromBackup -RepoRoot $repoRoot -BackupRoot $stateBackup
  }
  elseif (Test-Path $stateBackup) {
    Remove-Item -Path $stateBackup -Recurse -Force
  }
  Pop-Location
}
