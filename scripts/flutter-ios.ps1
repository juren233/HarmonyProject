param(
  [ValidateSet('prepare', 'pods', 'build', 'run')]
  [string]$Mode = 'prepare',
  [ValidateSet('debug', 'profile', 'release')]
  [string]$BuildMode = 'debug',
  [string]$DeviceId
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
    throw 'iOS build and run require macOS with Xcode installed. Use -Mode prepare on Windows to sync the project OHOS Flutter state only.'
  }
}

function Resolve-CocoaPods {
  return Resolve-ExistingPath -Candidates @('pod', '/opt/homebrew/bin/pod', '/usr/local/bin/pod') -Label 'CocoaPods'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sdkRepoRoot = Join-Path $repoRoot '.flutter_ohos_sdk_gitcode'
$resolvedSdkRepoRoot = (Resolve-Path $sdkRepoRoot).Path
$flutterSdkCandidates = @(
  (Join-Path $resolvedSdkRepoRoot 'bin\flutter.bat'),
  (Join-Path $resolvedSdkRepoRoot 'bin\flutter')
)
$flutterSdk = Resolve-ExistingPath -Candidates $flutterSdkCandidates -Label 'Flutter SDK'

Push-Location $repoRoot
try {
  Invoke-Checked -Executable $flutterSdk -Arguments @('pub', 'get')

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
