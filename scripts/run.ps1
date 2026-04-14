param(
  [ValidateSet('build', 'test')]
  [string]$Mode = 'build'
)

$ErrorActionPreference = 'Stop'

function Find-Tool {
  param(
    [string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return (Resolve-Path $candidate).Path
    }
  }

  return $null
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

$repoRoot = Split-Path -Parent $PSScriptRoot
$devEcoHome = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } elseif (Test-Path 'E:\Huawei\DevEco Studio') { 'E:\Huawei\DevEco Studio' } else { 'C:\Program Files\Huawei\DevEco Studio' }
$sdkHomeCandidates = @(
  $env:DEVECO_SDK_HOME,
  (Join-Path $devEcoHome 'sdk')
)
$hvigorCandidates = @(
  (Join-Path $devEcoHome 'tools\hvigor\bin\hvigorw.bat'),
  'hvigorw.bat'
)
$ohpmCandidates = @(
  (Join-Path $devEcoHome 'tools\ohpm\bin\ohpm.bat'),
  'ohpm.bat'
)

$sdkHome = Find-Tool -Candidates $sdkHomeCandidates
$hvigor = Find-Tool -Candidates $hvigorCandidates
$ohpm = Find-Tool -Candidates $ohpmCandidates

if (-not $sdkHome) {
  throw 'DEVECO_SDK_HOME was not found. Please install HarmonyOS SDK or configure the environment variable.'
}

if (-not $hvigor) {
  throw 'hvigorw.bat was not found. Please install DevEco Studio tooling.'
}

if (-not $ohpm) {
  throw 'ohpm.bat was not found. Please install DevEco Studio tooling.'
}

$env:DEVECO_SDK_HOME = $sdkHome

Push-Location $repoRoot
try {
  Invoke-Checked -Executable $ohpm -Arguments @('install', '--all')

  switch ($Mode) {
    'test' {
      Invoke-Checked -Executable $hvigor -Arguments @('test')
    }
    'build' {
      Invoke-Checked -Executable $hvigor -Arguments @('assembleApp')
    }
  }
}
finally {
  Pop-Location
}
