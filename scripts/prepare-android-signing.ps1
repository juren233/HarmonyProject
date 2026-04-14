param(
  [string]$RepoRoot,
  [string]$KeystoreBase64,
  [string]$KeystoreFile,
  [string]$StorePassword,
  [string]$KeyAlias,
  [string]$KeyPassword,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-FirstNonEmpty {
  param(
    [string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
      return $candidate.Trim()
    }
  }

  return $null
}

function Write-Utf8NoBomFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$resolvedRepoRoot = [string](Resolve-Path -LiteralPath $RepoRoot).ProviderPath
$androidDir = [System.IO.Path]::Combine($resolvedRepoRoot, 'android')
$keyPropertiesPath = [System.IO.Path]::Combine($androidDir, 'key.properties')
$signingDir = [System.IO.Path]::Combine($androidDir, 'signing')
# Android 统一使用仓库内固定相对路径，方便 Gradle、本机和 GitHub Actions 共用同一份配置协议。
$keystoreTargetFileName = 'pet-release.jks'

$resolvedKeystoreBase64 = Get-FirstNonEmpty -Candidates @($KeystoreBase64, $env:ANDROID_KEYSTORE_BASE64)
$resolvedKeystoreFile = Get-FirstNonEmpty -Candidates @($KeystoreFile, $env:ANDROID_KEYSTORE_FILE)
$resolvedStorePassword = Get-FirstNonEmpty -Candidates @($StorePassword, $env:ANDROID_KEYSTORE_PASSWORD)
$resolvedKeyAlias = Get-FirstNonEmpty -Candidates @($KeyAlias, $env:ANDROID_KEY_ALIAS)
$resolvedKeyPassword = Get-FirstNonEmpty -Candidates @($KeyPassword, $env:ANDROID_KEY_PASSWORD)

$hasExplicitInput = -not [string]::IsNullOrWhiteSpace($resolvedKeystoreBase64) `
  -or -not [string]::IsNullOrWhiteSpace($resolvedKeystoreFile) `
  -or -not [string]::IsNullOrWhiteSpace($resolvedStorePassword) `
  -or -not [string]::IsNullOrWhiteSpace($resolvedKeyAlias) `
  -or -not [string]::IsNullOrWhiteSpace($resolvedKeyPassword)

if (-not $Force -and -not $hasExplicitInput -and (Test-Path $keyPropertiesPath) -and (Test-Path ([System.IO.Path]::Combine($signingDir, $keystoreTargetFileName)))) {
  Write-Host "Android release signing is already prepared at $keyPropertiesPath"
  return
}

if ([string]::IsNullOrWhiteSpace($resolvedKeystoreBase64) -and [string]::IsNullOrWhiteSpace($resolvedKeystoreFile)) {
  throw "Android release signing is not configured. Provide ANDROID_KEYSTORE_FILE or ANDROID_KEYSTORE_BASE64 before running this script."
}

if (-not [string]::IsNullOrWhiteSpace($resolvedKeystoreBase64) -and -not [string]::IsNullOrWhiteSpace($resolvedKeystoreFile)) {
  throw 'Provide only one keystore source: ANDROID_KEYSTORE_FILE or ANDROID_KEYSTORE_BASE64.'
}

foreach ($required in @(
  @{ Name = 'ANDROID_KEYSTORE_PASSWORD'; Value = $resolvedStorePassword },
  @{ Name = 'ANDROID_KEY_ALIAS'; Value = $resolvedKeyAlias },
  @{ Name = 'ANDROID_KEY_PASSWORD'; Value = $resolvedKeyPassword }
)) {
  if ([string]::IsNullOrWhiteSpace($required.Value)) {
    throw "Missing required signing value: $($required.Name)"
  }
}

New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace($resolvedKeystoreBase64)) {
  try {
    $keystoreBytes = [System.Convert]::FromBase64String($resolvedKeystoreBase64)
  }
  catch {
    throw 'ANDROID_KEYSTORE_BASE64 is not valid Base64 content.'
  }

  if ($keystoreBytes.Length -eq 0) {
    throw 'ANDROID_KEYSTORE_BASE64 decoded to an empty keystore file.'
  }

  [System.IO.File]::WriteAllBytes(([System.IO.Path]::Combine($signingDir, $keystoreTargetFileName)), $keystoreBytes)
}
else {
  if (-not (Test-Path $resolvedKeystoreFile)) {
    throw "ANDROID_KEYSTORE_FILE was not found: $resolvedKeystoreFile"
  }

  $sourceKeystorePath = [string](Resolve-Path -LiteralPath $resolvedKeystoreFile).ProviderPath
  $targetKeystorePath = [System.IO.Path]::Combine($signingDir, $keystoreTargetFileName)

  if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($sourceKeystorePath, $targetKeystorePath)) {
    Copy-Item -LiteralPath $sourceKeystorePath -Destination $targetKeystorePath -Force
  }
}

$keyPropertiesContent = @"
storePassword=$resolvedStorePassword
keyPassword=$resolvedKeyPassword
keyAlias=$resolvedKeyAlias
storeFile=signing/pet-release.jks
"@

Write-Utf8NoBomFile -Path $keyPropertiesPath -Content $keyPropertiesContent
Write-Host "Prepared Android release signing at $keyPropertiesPath"
