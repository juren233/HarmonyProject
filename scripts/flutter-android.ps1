param(
  [ValidateSet('build', 'install', 'run')]
  [string]$Mode = 'build',
  [ValidateSet('debug', 'profile', 'release')]
  [string]$BuildMode = 'release',
  [ValidateSet('arm64', 'arm', 'arm64+arm', 'x64')]
  [string]$TargetPlatform = 'arm64',
  [string]$DeviceId
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
    [string[]]$Arguments
  )

  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Executable $($Arguments -join ' ')"
  }
}

function Get-PropertiesMap {
  param(
    [string]$Path
  )

  $properties = @{}
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

function Get-AndroidPackageName {
  param(
    [string]$GradlePath
  )

  $match = Select-String -Path $GradlePath -Pattern 'applicationId\s*=\s*"([^"]+)"' | Select-Object -First 1
  if (-not $match) {
    throw "Could not find applicationId in $GradlePath"
  }

  return $match.Matches[0].Groups[1].Value
}

function Get-LaunchActivityName {
  param(
    [string]$ManifestPath,
    [string]$PackageName
  )

  [xml]$manifest = Get-Content -Path $ManifestPath
  $launcherActivity = $null

  foreach ($activity in $manifest.manifest.application.activity) {
    foreach ($intentFilter in $activity.'intent-filter') {
      $actions = @($intentFilter.action | ForEach-Object { $_.GetAttribute('android:name') })
      $categories = @($intentFilter.category | ForEach-Object { $_.GetAttribute('android:name') })

      if ($actions -contains 'android.intent.action.MAIN' -and $categories -contains 'android.intent.category.LAUNCHER') {
        $launcherActivity = $activity.GetAttribute('android:name')
        break
      }
    }

    if ($launcherActivity) {
      break
    }
  }

  if (-not $launcherActivity) {
    throw "Could not find launch activity in $ManifestPath"
  }

  if ($launcherActivity.StartsWith('.')) {
    return "$PackageName$launcherActivity"
  }

  return $launcherActivity
}

function Get-TargetPlatformArg {
  param(
    [string]$Value
  )

  switch ($Value) {
    'arm64' { return 'android-arm64' }
    'arm' { return 'android-arm' }
    'arm64+arm' { return 'android-arm,android-arm64' }
    'x64' { return 'android-x64' }
    default { throw "Unsupported target platform: $Value" }
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repoRoot 'android'
$localPropertiesPath = Join-Path $androidDir 'local.properties'

if (-not (Test-Path $localPropertiesPath)) {
  throw "Android local.properties was not found at $localPropertiesPath"
}

$localProperties = Get-PropertiesMap -Path $localPropertiesPath
$flutterSdk = Resolve-ExistingPath -Candidates @(
  'E:\flutter\bin\flutter.bat',
  $(if ($localProperties.ContainsKey('flutter.sdk')) { Join-Path $localProperties['flutter.sdk'] 'bin\flutter.bat' }),
  'flutter.bat',
  'flutter'
) -Label 'Flutter SDK'
$androidSdk = Resolve-ExistingPath -Candidates @(
  $localProperties['sdk.dir'],
  $env:ANDROID_SDK_ROOT,
  $env:ANDROID_HOME
) -Label 'Android SDK'

$adb = Resolve-ExistingPath -Candidates @(
  (Join-Path $androidSdk 'platform-tools\adb.exe'),
  'adb.exe',
  'adb'
) -Label 'adb'

$targetPlatformArg = Get-TargetPlatformArg -Value $TargetPlatform
$apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-$BuildMode.apk"
$packageName = Get-AndroidPackageName -GradlePath (Join-Path $androidDir 'app\build.gradle')
$activityName = Get-LaunchActivityName `
  -ManifestPath (Join-Path $androidDir 'app\src\main\AndroidManifest.xml') `
  -PackageName $packageName

$env:ANDROID_SDK_ROOT = $androidSdk
$env:ANDROID_HOME = $androidSdk

Push-Location $repoRoot
try {
  Restore-PlatformState -RepoRoot $repoRoot -StateName 'official' | Out-Null
  Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
  Save-PlatformState -RepoRoot $repoRoot -StateName 'official'

  $buildArguments = @(
    'build',
    'apk',
    "--$BuildMode",
    '--target-platform',
    $targetPlatformArg
  )
  if ($BuildMode -eq 'release') {
    $buildArguments += '--no-tree-shake-icons'
  }
  Invoke-Checked -Executable $flutterSdk -Arguments $buildArguments

  if (-not (Test-Path $apkPath)) {
    throw "Expected APK was not generated at $apkPath"
  }

  if ($Mode -eq 'install' -or $Mode -eq 'run') {
    $installArguments = @()
    if ($DeviceId) {
      $installArguments += @('-s', $DeviceId)
    }
    $installArguments += @('install', '-r', $apkPath)
    Invoke-Checked -Executable $adb -Arguments $installArguments
  }

  if ($Mode -eq 'run') {
    $runArguments = @()
    if ($DeviceId) {
      $runArguments += @('-s', $DeviceId)
    }
    $runArguments += @('shell', 'am', 'start', '-n', "$packageName/$activityName")
    Invoke-Checked -Executable $adb -Arguments $runArguments
  }
}
finally {
  Pop-Location
}
