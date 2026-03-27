param(
  [ValidateSet('prepare', 'pods', 'build', 'run')]
  [string]$Mode = 'prepare',
  [ValidateSet('debug', 'profile', 'release')]
  [string]$BuildMode = 'debug',
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

function Invoke-CheckedInDirectory {
  param(
    [string]$WorkingDirectory,
    [string]$Executable,
    [string[]]$Arguments
  )

  Push-Location $WorkingDirectory
  try {
    Invoke-Checked -Executable $Executable -Arguments $Arguments
  }
  finally {
    Pop-Location
  }
}

function Assert-MacOS {
  $isMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
  )
  if (-not $isMacOS) {
    throw 'iOS build and run require macOS with Xcode installed. Use -Mode prepare on Windows to sync the official Flutter state only.'
  }
}

function Resolve-CocoaPods {
  return Resolve-ExistingPath -Candidates @('pod', '/opt/homebrew/bin/pod', '/usr/local/bin/pod') -Label 'CocoaPods'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidLocalPropertiesPath = Join-Path $repoRoot 'android\local.properties'
$flutterSdkCandidates = @('E:\flutter\bin\flutter.bat', 'E:\flutter\bin\flutter')

if (Test-Path $androidLocalPropertiesPath) {
  $androidFlutterSdk = Select-String -Path $androidLocalPropertiesPath -Pattern '^flutter\.sdk=(.+)$' | Select-Object -First 1
  if ($androidFlutterSdk) {
    $flutterRoot = $androidFlutterSdk.Matches[0].Groups[1].Value.Trim().Replace('\\', '\')
    $flutterSdkCandidates += @(
      (Join-Path $flutterRoot 'bin\flutter.bat'),
      (Join-Path $flutterRoot 'bin\flutter')
    )
  }
}

$flutterSdkCandidates += 'flutter.bat'
$flutterSdkCandidates += 'flutter'
$flutterSdk = Resolve-ExistingPath -Candidates $flutterSdkCandidates -Label 'Flutter SDK'

Push-Location $repoRoot
try {
  Restore-PlatformState -RepoRoot $repoRoot -StateName 'official' | Out-Null
  Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')
  Save-PlatformState -RepoRoot $repoRoot -StateName 'official'

  if ($Mode -eq 'prepare') {
    return
  }

  Assert-MacOS
  $pod = Resolve-CocoaPods
  $iosDir = Join-Path $repoRoot 'ios'
  Invoke-CheckedInDirectory -WorkingDirectory $iosDir -Executable $pod -Arguments @('install')

  if ($Mode -eq 'pods') {
    return
  }

  if ($Mode -eq 'build') {
    $buildArguments = @(
      'build',
      'ios',
      "--$BuildMode",
      '--no-codesign',
      '--no-tree-shake-icons'
    )
    Invoke-Checked -Executable $flutterSdk -Arguments $buildArguments
    return
  }

  $runArguments = @('run', "--$BuildMode")
  if ($DeviceId) {
    $runArguments += @('-d', $DeviceId)
  }
  Invoke-Checked -Executable $flutterSdk -Arguments $runArguments
}
finally {
  Pop-Location
}
