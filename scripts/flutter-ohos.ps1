param(
  [ValidateSet('test', 'build', 'install', 'run')]
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

function Invoke-Checked {
  param(
    [string]$Executable,
    [string[]]$Arguments
  )

  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
  }
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

  $udid = (($output | Select-String '([A-F0-9]{64})').Matches.Value | Select-Object -First 1)
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
$flutterSdk = Resolve-ExistingPath -Candidates @(
  (Join-Path $repoRoot '.flutter_ohos_sdk_gitcode\bin\flutter.bat'),
  (Join-Path $repoRoot '.flutter_ohos_sdk\bin\flutter.bat')
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
$packInfo = Join-Path $repoRoot 'ohos\entry\build\default\outputs\default\pack.info'
$bundleInfo = Get-Content (Join-Path $repoRoot 'ohos\AppScope\app.json5') -Raw | ConvertFrom-Json
$bundleName = [string]$bundleInfo.app.bundleName
$abilityName = 'EntryAbility'
$keystorePassword = '123456'

Push-Location $repoRoot
try {
  if ($Mode -eq 'test') {
    Invoke-Checked -Executable $flutterSdk -Arguments @('test')
    return
  }

  $keytool = Resolve-ExistingPath -Candidates @('keytool.exe', 'keytool') -Label 'keytool'
  $hdc = Resolve-ExistingPath -Candidates @(
    (Join-Path $ohToolchainDir 'hdc.exe'),
    'hdc.exe',
    'hdc'
  ) -Label 'hdc'

  New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

  Invoke-AllowingUnsignedBuild `
    -Executable $flutterSdk `
    -Arguments @('build', 'hap', '--debug', '--target-platform', "ohos-$TargetPlatform") `
    -UnsignedHapPath $unsignedHap

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
  Pop-Location
}
