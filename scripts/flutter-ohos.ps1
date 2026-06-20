param(
  [ValidateSet('init', 'test', 'build', 'install', 'run')]
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

function Resolve-CommandDirectory {
  param(
    [string[]]$Candidates,
    [string]$Label
  )

  foreach ($candidate in $Candidates) {
    if (-not $candidate) {
      continue
    }

    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
      return (Split-Path $command.Source -Parent)
    }
  }

  throw "$Label was not found."
}

function Get-OptionalCommandDirectory {
  param(
    [string[]]$Candidates
  )

  try {
    return Resolve-CommandDirectory -Candidates $Candidates -Label ($Candidates -join '/')
  }
  catch {
    return $null
  }
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

function Get-PropertiesMap {
  param(
    [string]$Path
  )

  $properties = @{}
  if (-not (Test-Path $Path)) {
    return $properties
  }

  foreach ($line in Get-Content -Path $Path) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
      continue
    }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) {
      continue
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim().Replace('\\', '\')
    $properties[$key] = $value
  }

  return $properties
}

function Convert-ToPropertiesPathValue {
  param(
    [string]$Value
  )

  return $Value.Replace('\', '\\')
}

function Get-PubspecVersionInfo {
  param(
    [string]$RepoRoot
  )

  $pubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
  if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml was not found at $pubspecPath"
  }

  $versionValue = $null
  foreach ($line in Get-Content -Path $pubspecPath) {
    $trimmedLine = $line.Trim()
    if ($trimmedLine.StartsWith('version:')) {
      $versionValue = $trimmedLine.Substring('version:'.Length).Trim()
      break
    }
  }

  if ([string]::IsNullOrWhiteSpace($versionValue)) {
    throw "Could not find version in $pubspecPath"
  }

  $versionParts = $versionValue -split '\+', 2
  $versionName = $versionParts[0].Trim()
  $versionCode = if ($versionParts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($versionParts[1])) {
    $versionParts[1].Trim()
  }
  else {
    '1'
  }

  if ([string]::IsNullOrWhiteSpace($versionName)) {
    throw "pubspec.yaml versionName must not be empty."
  }

  [long]$parsedVersionCode = 0
  if (-not [long]::TryParse($versionCode, [ref]$parsedVersionCode)) {
    throw "pubspec.yaml build number must be numeric: $versionCode"
  }

  return [pscustomobject]@{
    VersionName = $versionName
    VersionCode = [string]$parsedVersionCode
  }
}

function Ensure-OhosLocalProperties {
  param(
    [string]$LocalPropertiesPath,
    [string]$DevEcoSdkHome,
    [string]$NodejsDir,
    [string]$FlutterSdkRoot,
    [string]$VersionName,
    [string]$VersionCode
  )

  $content = @(
    "hwsdk.dir=$(Convert-ToPropertiesPathValue -Value $DevEcoSdkHome)"
    "nodejs.dir=$(Convert-ToPropertiesPathValue -Value $NodejsDir)"
    "flutter.sdk=$(Convert-ToPropertiesPathValue -Value $FlutterSdkRoot)"
    "flutter.versionName=$versionName"
    "flutter.versionCode=$versionCode"
  ) -join "`r`n"
  $desiredContent = $content + "`r`n"

  $currentContent = if (Test-Path $LocalPropertiesPath) {
    (Get-Content -Path $LocalPropertiesPath -Raw).Replace("`r`n", "`n")
  }
  else {
    $null
  }
  $normalizedDesiredContent = $desiredContent.Replace("`r`n", "`n")

  if ($currentContent -eq $normalizedDesiredContent) {
    return
  }

  Set-Content -Path $LocalPropertiesPath -Value $desiredContent -Encoding ascii
}

function Ensure-HvigorPluginPatched {
  param(
    [string]$FilePath
  )

  if (-not (Test-Path $FilePath)) {
    return
  }

  $originalContent = (Get-Content -Path $FilePath -Raw).Replace("`r`n", "`n")
  $content = $originalContent

  $refreshStartMarker = "console.info('Refresh Flutter package config for OHOS IDE run start')"
  $backupStateMarker = "console.info('Backup Flutter shared state start')"
  $pluginGuardMarker = 'findOhosPluginsFromDependencyGraph'

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
      const flutterOhosStorePath = getFlutterOhosStorePath(flutterProjectPath)
      clearStaleFlutterOhosArkTsCache(flutterProjectPath, flutterOhosStorePath)
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

  $oldPluginsPathAssignments = @(
    "const flutterPluginsDependenciesPath = path.join(flutterProjectPath, '.flutter-plugins-dependencies')"
  )
  foreach ($oldPluginsPathAssignment in $oldPluginsPathAssignments) {
    if ($content.Contains($oldPluginsPathAssignment)) {
      $content = $content.Replace(
        $oldPluginsPathAssignment,
        "const flutterPluginsDependenciesPath = getFlutterPluginsDependenciesPath(flutterProjectPath)"
      )
    }
  }

  if ($content -eq $originalContent) {
    return
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
    [string]$VersionName,
    [string]$VersionCode,
    [string]$OutFile
  )

  $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $template.'version-name' = $VersionName
  $template.'version-code' = [int64]$VersionCode
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

function Inject-FlutterOhosPluginDependencies {
  param(
    [string]$RepoRoot
  )

  $entryOhPackagePath = Join-Path $RepoRoot 'ohos\entry\oh-package.json5'
  $pluginsDepsPath = Join-Path $RepoRoot '.flutter-plugins-dependencies'

  if (-not (Test-Path $entryOhPackagePath) -or -not (Test-Path $pluginsDepsPath)) {
    return $null
  }

  $pluginsDeps = Get-Content $pluginsDepsPath -Raw | ConvertFrom-Json
  $ohosPlugins = $pluginsDeps.plugins.ohos
  if (-not $ohosPlugins -or $ohosPlugins.Count -eq 0) {
    return $null
  }

  $entryOhPackage = Get-Content $entryOhPackagePath -Raw
  $backupContent = $entryOhPackage

  $ohPackageJson = $entryOhPackage | ConvertFrom-Json
  if (-not $ohPackageJson.dependencies) {
    $ohPackageJson | Add-Member -NotePropertyName 'dependencies' -NotePropertyValue @{} -Force
  }

  $modified = $false
  foreach ($plugin in $ohosPlugins) {
    $pluginName = $plugin.name
    if ($ohPackageJson.dependencies.PSObject.Properties.Name -contains $pluginName) {
      continue
    }

    $pluginPath = $plugin.path
    if (-not $pluginPath) {
      continue
    }

    $pluginOhosDir = Join-Path $pluginPath 'ohos'
    if (-not (Test-Path $pluginOhosDir)) {
      continue
    }

    $ohPackageJson.dependencies | Add-Member -NotePropertyName $pluginName -NotePropertyValue "file:$pluginOhosDir" -Force
    $modified = $true
  }

  if ($modified) {
    $ohPackageJson | ConvertTo-Json -Depth 10 | Set-Content -Path $entryOhPackagePath -Encoding utf8
    return $backupContent
  }

  return $null
}

function Restore-FlutterOhosPluginDependencies {
  param(
    [string]$RepoRoot,
    [string]$BackupContent
  )

  if (-not $BackupContent) {
    return
  }

  $entryOhPackagePath = Join-Path $RepoRoot 'ohos\entry\oh-package.json5'
  Set-Content -Path $entryOhPackagePath -Value $BackupContent -Encoding utf8
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspecVersionInfo = Get-PubspecVersionInfo -RepoRoot $repoRoot
$sdkRepoRoot = Join-Path $repoRoot '.flutter_ohos_sdk_gitcode'
Ensure-OhosFlutterSubmodule -RepoRoot $repoRoot -SubmodulePath $sdkRepoRoot
$resolvedSdkRepoRoot = (Resolve-Path $sdkRepoRoot).Path
$flutterSdk = Resolve-ExistingPath -Candidates @(
  (Join-Path $sdkRepoRoot 'bin\flutter.bat')
) -Label 'Flutter OH SDK'
$ohosLocalPropertiesPath = Join-Path $repoRoot 'ohos\local.properties'
$existingOhosLocalProperties = Get-PropertiesMap -Path $ohosLocalPropertiesPath
$devEcoHomeFromEnv = $null
if ($env:DEVECO_HOME) {
  $devEcoHomeFromEnv = $env:DEVECO_HOME
}
$devEcoSdkHomeFromEnv = $null
if ($env:DEVECO_SDK_HOME) {
  $devEcoSdkHomeFromEnv = $env:DEVECO_SDK_HOME
}
$devEcoSdkHomeFromDevEcoHome = $null
if ($devEcoHomeFromEnv) {
  $devEcoSdkHomeFromDevEcoHome = Join-Path $devEcoHomeFromEnv 'sdk'
}
$derivedDevEcoStudioRoot = $null
if ($existingOhosLocalProperties['nodejs.dir']) {
  try {
    $derivedDevEcoStudioRoot = Split-Path (Split-Path $existingOhosLocalProperties['nodejs.dir'] -Parent) -Parent
  }
  catch {
    $derivedDevEcoStudioRoot = $null
  }
}
$devEcoHome = Resolve-ExistingPath -Candidates @(
  $devEcoHomeFromEnv,
  $derivedDevEcoStudioRoot,
  $(if ($devEcoSdkHomeFromEnv) { Split-Path $devEcoSdkHomeFromEnv -Parent }),
  $(if ($existingOhosLocalProperties['hwsdk.dir']) { Split-Path $existingOhosLocalProperties['hwsdk.dir'] -Parent }),
  'C:\Program Files\Huawei\DevEco Studio',
  'E:\Huawei\DevEco Studio'
) -Label 'DevEco Studio'
$devEcoSdkHome = Resolve-ExistingPath -Candidates @(
  $devEcoSdkHomeFromEnv,
  $devEcoSdkHomeFromDevEcoHome,
  (Join-Path $devEcoHome 'sdk'),
  $existingOhosLocalProperties['hwsdk.dir'],
  'C:\Program Files\Huawei\DevEco Studio\sdk',
  'E:\Huawei\DevEco Studio\sdk'
) -Label 'DevEco SDK'
$devEcoNodeDir = Resolve-ExistingPath -Candidates @(
  $env:DEVECO_NODEJS_HOME,
  $existingOhosLocalProperties['nodejs.dir'],
  $(if ($devEcoHomeFromEnv) { Join-Path $devEcoHomeFromEnv 'tools\node' }),
  (Join-Path $devEcoHome 'tools\node'),
  (Get-OptionalCommandDirectory -Candidates @('node.exe', 'node'))
) -Label 'DevEco Node.js'
$devEcoOhpmBin = Resolve-ExistingPath -Candidates @(
  $(if ($devEcoHomeFromEnv) { Join-Path $devEcoHomeFromEnv 'tools\ohpm\bin' }),
  (Join-Path $devEcoHome 'tools\ohpm\bin'),
  (Get-OptionalCommandDirectory -Candidates @('ohpm.cmd', 'ohpm'))
) -Label 'DevEco ohpm'
$devEcoHvigorBin = Resolve-ExistingPath -Candidates @(
  $(if ($devEcoHomeFromEnv) { Join-Path $devEcoHomeFromEnv 'tools\hvigor\bin' }),
  (Join-Path $devEcoHome 'tools\hvigor\bin'),
  (Get-OptionalCommandDirectory -Candidates @('hvigorw.bat', 'hvigorw'))
) -Label 'DevEco hvigor'
$ohToolchainDir = Resolve-ExistingPath -Candidates @(
  $env:HARMONY_TOOLCHAIN_HOME,
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
  (Join-Path $repoRoot 'ohos\sign\debug-profile.json'),
  (Join-Path $ohToolchainDir 'lib\UnsgnedDebugProfileTemplate.json')
) -Label 'UnsgnedDebugProfileTemplate.json'

$env:DEVECO_SDK_HOME = $devEcoSdkHome
$env:PUB_CACHE = (Join-Path (Split-Path $repoRoot -Parent) 'pub_cache')
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:FLUTTER_GIT_URL = 'https://gitcode.com/openharmony-tpc/flutter_flutter.git'
$env:Path = @(
  (Split-Path $flutterSdk -Parent),
  $devEcoOhpmBin,
  $devEcoHvigorBin,
  $devEcoNodeDir,
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
  Ensure-OhosLocalProperties `
    -LocalPropertiesPath $ohosLocalPropertiesPath `
    -DevEcoSdkHome $devEcoSdkHome `
    -NodejsDir $devEcoNodeDir `
    -FlutterSdkRoot $resolvedSdkRepoRoot `
    -VersionName $pubspecVersionInfo.VersionName `
    -VersionCode $pubspecVersionInfo.VersionCode

  if ($Mode -eq 'init') {
    Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
    Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot
    Save-PlatformState -RepoRoot $repoRoot -StateName 'ohos'
    return
  }

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

  # Remove stale HAP outputs from previous builds so a failed build cannot
  # silently fall through to installing an outdated artifact.
  foreach ($staleHap in @($unsignedHap, $signedHap, $builtSignedHap)) {
    if (Test-Path $staleHap) {
      Remove-Item -Path $staleHap -Force
    }
  }

  $injectedOhPackageBackup = Inject-FlutterOhosPluginDependencies -RepoRoot $repoRoot
  try {
    Invoke-AllowingUnsignedBuild `
      -Executable $flutterSdk `
      -Arguments @('build', 'hap', '--debug', '--target-platform', "ohos-$TargetPlatform", '--no-tree-shake-icons') `
      -UnsignedHapPath $unsignedHap
  }
  finally {
    Restore-FlutterOhosPluginDependencies -RepoRoot $repoRoot -BackupContent $injectedOhPackageBackup
  }
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
  New-DebugProfileJson `
    -TemplatePath $profileTemplate `
    -BundleName $bundleName `
    -DeviceUdid $deviceUdid `
    -VersionName $pubspecVersionInfo.VersionName `
    -VersionCode $pubspecVersionInfo.VersionCode `
    -OutFile $profileJson

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
  $restoredOfficialState = Restore-PlatformState -RepoRoot $repoRoot -StateName 'ohos'
  if (-not $restoredOfficialState) {
    Restore-ManagedStateFromBackup -RepoRoot $repoRoot -BackupRoot $stateBackup
  }
  elseif (Test-Path $stateBackup) {
    Remove-Item -Path $stateBackup -Recurse -Force
  }
  Pop-Location
}
