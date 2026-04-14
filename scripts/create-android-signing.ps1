param(
  [string]$RepoRoot,
  [string]$OutputDirectory,
  [string]$KeystoreFileName = 'pet-release.jks',
  [string]$Alias = 'petnote_release',
  [string]$StorePassword,
  [string]$KeyPassword,
  [string]$CommonName = 'PetNote Android Release',
  [string]$OrganizationUnit = 'Mobile',
  [string]$Organization = 'PetNote',
  [string]$Locality = 'Shanghai',
  [string]$State = 'Shanghai',
  [string]$Country = 'CN',
  [int]$ValidityDays = 36500,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function New-RandomSecret {
  param(
    [int]$Length = 24
  )

  $bytes = New-Object byte[] ($Length)
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $value = [Convert]::ToBase64String($bytes)
  $value = $value.Replace('+', 'A').Replace('/', 'b').Replace('=', '9')
  if ($value.Length -lt $Length) {
    return ($value + ('X' * ($Length - $value.Length)))
  }

  return $value.Substring(0, $Length)
}

function Resolve-Keytool {
  $command = Get-Command keytool -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  throw 'keytool was not found.'
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $env:USERPROFILE '.petnote-signing'
}

$resolvedOutputDirectory = $OutputDirectory
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null
$keystorePath = Join-Path $resolvedOutputDirectory $KeystoreFileName

if ((Test-Path $keystorePath) -and -not $Force) {
  throw "Keystore already exists at $keystorePath. Use -Force only when you have confirmed replacing it is safe."
}

$resolvedStorePassword = if ([string]::IsNullOrWhiteSpace($StorePassword)) { New-RandomSecret } else { $StorePassword.Trim() }
$resolvedKeyPassword = if ([string]::IsNullOrWhiteSpace($KeyPassword)) { New-RandomSecret } else { $KeyPassword.Trim() }
$distinguishedName = "CN=$CommonName, OU=$OrganizationUnit, O=$Organization, L=$Locality, ST=$State, C=$Country"
$keytool = Resolve-Keytool

if (Test-Path $keystorePath) {
  Remove-Item -Force $keystorePath
}

& $keytool `
  -genkeypair `
  -v `
  -keystore $keystorePath `
  -storetype JKS `
  -alias $Alias `
  -keyalg RSA `
  -keysize 2048 `
  -validity $ValidityDays `
  -storepass $resolvedStorePassword `
  -keypass $resolvedKeyPassword `
  -dname $distinguishedName
if ($LASTEXITCODE -ne 0) {
  throw "keytool failed with exit code ${LASTEXITCODE}"
}

$prepareSigningScript = Join-Path $PSScriptRoot 'prepare-android-signing.ps1'
if (-not (Test-Path $prepareSigningScript)) {
  throw "Android signing helper script was not found at $prepareSigningScript"
}

$env:ANDROID_KEYSTORE_FILE = $keystorePath
$env:ANDROID_KEYSTORE_PASSWORD = $resolvedStorePassword
$env:ANDROID_KEY_ALIAS = $Alias
$env:ANDROID_KEY_PASSWORD = $resolvedKeyPassword

try {
  & $prepareSigningScript -RepoRoot $resolvedRepoRoot -Force
  if ($LASTEXITCODE -ne 0) {
    throw "Android signing helper script failed with exit code ${LASTEXITCODE}"
  }
}
finally {
  Remove-Item Env:ANDROID_KEYSTORE_FILE -ErrorAction SilentlyContinue
  Remove-Item Env:ANDROID_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:ANDROID_KEY_ALIAS -ErrorAction SilentlyContinue
  Remove-Item Env:ANDROID_KEY_PASSWORD -ErrorAction SilentlyContinue
}

$fingerprintOutput = & $keytool -list -v -keystore $keystorePath -storepass $resolvedStorePassword -alias $Alias
if ($LASTEXITCODE -ne 0) {
  throw "keytool fingerprint check failed with exit code ${LASTEXITCODE}"
}

$summary = [ordered]@{
  keystorePath = $keystorePath
  alias = $Alias
  storePassword = $resolvedStorePassword
  keyPassword = $resolvedKeyPassword
  distinguishedName = $distinguishedName
}

$summaryJsonPath = Join-Path $resolvedOutputDirectory 'pet-release.summary.json'
$summary | ConvertTo-Json | Set-Content -Path $summaryJsonPath -Encoding UTF8

Write-Host "Created Android release signing:"
Write-Host "  keystorePath=$keystorePath"
Write-Host "  alias=$Alias"
Write-Host "  summary=$summaryJsonPath"
Write-Host $fingerprintOutput
