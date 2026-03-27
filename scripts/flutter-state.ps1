Set-StrictMode -Version Latest

function Get-ManagedFlutterStateFiles {
  return @(
    'pubspec.lock',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.dart_tool/package_config.json',
    '.dart_tool/package_config_subset',
    '.dart_tool/package_graph.json',
    '.dart_tool/version',
    'android/local.properties',
    'ohos/local.properties'
  )
}

function Remove-PathIfExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (Test-Path $Path) {
    Remove-Item -Path $Path -Force
  }
}

function Copy-FilePreservingParent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  $destinationDir = Split-Path -Parent $DestinationPath
  if ($destinationDir) {
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
  }

  Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
}

function Get-FlutterStateRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$StateName
  )

  return Join-Path $RepoRoot ".tooling\flutter-state\$StateName"
}

function Restore-PlatformState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$StateName
  )

  $stateRoot = Get-FlutterStateRoot -RepoRoot $RepoRoot -StateName $StateName
  if (-not (Test-Path $stateRoot)) {
    return $false
  }

  foreach ($relativePath in Get-ManagedFlutterStateFiles) {
    $sourcePath = Join-Path $stateRoot $relativePath
    $targetPath = Join-Path $RepoRoot $relativePath

    if (Test-Path $sourcePath) {
      Copy-FilePreservingParent -SourcePath $sourcePath -DestinationPath $targetPath
    }
    else {
      Remove-PathIfExists -Path $targetPath
    }
  }

  return $true
}

function Save-PlatformState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$StateName
  )

  $stateRoot = Get-FlutterStateRoot -RepoRoot $RepoRoot -StateName $StateName
  New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

  foreach ($relativePath in Get-ManagedFlutterStateFiles) {
    $sourcePath = Join-Path $RepoRoot $relativePath
    $targetPath = Join-Path $stateRoot $relativePath

    if (Test-Path $sourcePath) {
      Copy-FilePreservingParent -SourcePath $sourcePath -DestinationPath $targetPath
    }
    else {
      Remove-PathIfExists -Path $targetPath
    }
  }
}

function Backup-ManagedState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $backupRoot = Join-Path $RepoRoot ".tooling\flutter-state\.session-backups\$([guid]::NewGuid())"
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

  foreach ($relativePath in Get-ManagedFlutterStateFiles) {
    $sourcePath = Join-Path $RepoRoot $relativePath
    if (Test-Path $sourcePath) {
      Copy-FilePreservingParent -SourcePath $sourcePath -DestinationPath (Join-Path $backupRoot $relativePath)
    }
  }

  return $backupRoot
}

function Restore-ManagedStateFromBackup {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$BackupRoot
  )

  foreach ($relativePath in Get-ManagedFlutterStateFiles) {
    $backupPath = Join-Path $BackupRoot $relativePath
    $targetPath = Join-Path $RepoRoot $relativePath

    if (Test-Path $backupPath) {
      Copy-FilePreservingParent -SourcePath $backupPath -DestinationPath $targetPath
    }
    else {
      Remove-PathIfExists -Path $targetPath
    }
  }

  if (Test-Path $BackupRoot) {
    Remove-Item -Path $BackupRoot -Recurse -Force
  }
}
