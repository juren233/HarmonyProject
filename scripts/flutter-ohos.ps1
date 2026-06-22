param(
  [ValidateSet('init', 'test', 'build', 'install', 'run')]
  [string]$Mode = 'build',
  [ValidateSet('x64', 'arm64', 'arm')]
  [string]$TargetPlatform = 'x64',
  [string]$DeviceId = '127.0.0.1:5555'
)

$ErrorActionPreference = 'Stop'

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
try {
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
    return
  }

  if ($Mode -eq 'test') {
    Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
    Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot
    Invoke-Checked -Executable $flutterSdk -Arguments @('test')
    Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot
    return
  }

  Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
  Ensure-RepoOwnedHvigorPluginDependency -RepoRoot $repoRoot

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
  Pop-Location
}
