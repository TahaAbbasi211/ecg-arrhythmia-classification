<#
.SYNOPSIS
    Local release-signing helper for the ECG Beat Classifier Android app.

.DESCRIPTION
    Manages Android release signing keystores outside version control:

    -Action create  Recommended: generate a dedicated permanent release.jks keystore
                    for official and Play Store releases (clean cutover; users of
                    legacy debug-signed v2.0.0/v2.1.0 builds uninstall once).
    -Action rotate  Optional: create release.jks and an apksigner rotation lineage
                    from the legacy debug keystore for in-place sideloaded updates.
    -Action backup  Legacy fallback only: back up %USERPROFILE%\.android\debug.keystore
                    outside the repository (not recommended for production releases).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action create

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File signing_setup.ps1 -Action rotate
#>
param(
    [ValidateSet("create", "rotate", "backup")]
    [string]$Action = "create",
    [string]$Keystore = (Join-Path $env:USERPROFILE ".android\debug.keystore"),
    [string]$BackupDir = (Join-Path $env:USERPROFILE ("ecg-signing-backup-" + (Get-Date -Format "yyyyMMdd"))),
    [string]$NewKeystore = (Join-Path $PSScriptRoot "release.jks"),
    [string]$Lineage = (Join-Path $PSScriptRoot "lineage.bin"),
    [string]$Alias = "release",
    [string]$Dname = "CN=ECG Beat Classifier, O=local development, C=IR",
    [int]$ValidDays = 10000,
    [string]$Keytool = "",
    [string]$Apksigner = "",
    # Optional: skip the prompts (only for scripted runs; prompting is safer,
    # because command-line arguments end up in the shell history).
    [string]$NewPassword = "",
    [string]$OldPassword = ""
)

$ErrorActionPreference = "Stop"

function Resolve-Keytool {
    if ($Keytool) { return $Keytool }
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME "bin\keytool.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    $found = Get-Command keytool -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    throw "keytool not found. Install a JDK and set JAVA_HOME (for example JAVA_HOME=D:\toolchain\jdk21)."
}

function Resolve-Apksigner {
    if ($Apksigner) { return $Apksigner }
    $roots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT) | Where-Object { $_ }
    $local = Join-Path $PSScriptRoot "local.properties"
    if (Test-Path $local) {
        $line = Get-Content $local | Where-Object { $_ -match "^sdk\.dir=" } | Select-Object -First 1
        if ($line) { $roots += ($line -replace "^sdk\.dir=", "").Replace("\\", "\") }
    }
    foreach ($root in $roots) {
        $buildTools = Join-Path $root "build-tools"
        if (-not (Test-Path $buildTools)) { continue }
        $newest = Get-ChildItem $buildTools -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($newest) {
            $candidate = Join-Path $newest.FullName "apksigner.bat"
            if (Test-Path $candidate) { return $candidate }
        }
    }
    $found = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    throw "apksigner not found. Set ANDROID_HOME or add build-tools to PATH."
}

function New-Secret([string]$Label) {
    $secure = Read-Host -AsSecureString $Label
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

if ($Action -eq "backup") {
    if (-not (Test-Path $Keystore)) { throw "No keystore at $Keystore." }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Copy-Item -LiteralPath $Keystore -Destination (Join-Path $BackupDir "debug.keystore") -Force
    $hash = (Get-FileHash -LiteralPath $Keystore -Algorithm SHA256).Hash
    $cert = "804591F4D096CF6286BC18816BD2D524CA4EA10254E78756D1647039F9A16DE5"
    @"
ECG Beat Classifier - Legacy Android debug keystore backup

Source      : $Keystore
Copied      : $(Get-Date -Format "yyyy-MM-dd HH:mm")
File SHA-256: $hash
Certificate : CN=Android Debug
              SHA-256 $cert

Legacy archival copy only (used by earlier sideloaded v2.0.0 and v2.1.0 builds).
For official or future releases, generate a permanent release.jks via
`signing_setup.ps1 -Action create`. Keep this folder private and outside the repository.

Store password: android
Key alias     : androiddebugkey
Key password  : android
"@ | Set-Content -Path (Join-Path $BackupDir "README.txt") -Encoding UTF8
    Write-Host "Backed up legacy debug keystore to $BackupDir"
    Write-Host "File SHA-256 : $hash"
    Write-Host "Cert SHA-256 : $cert  (CN=Android Debug)"
    exit 0
}

if (Test-Path $NewKeystore) { throw "$NewKeystore already exists; refusing to overwrite it." }

$keytoolPath = Resolve-Keytool
$newPassword = if ($NewPassword) { $NewPassword } else { New-Secret "Password for the new $Alias key" }
if ($newPassword.Length -lt 6) { throw "Android keystore passwords must have at least 6 characters." }

if ($Action -eq "create") {
    Write-Host "Creating permanent release keystore $NewKeystore ..."
    & $keytoolPath -genkeypair -v -storetype PKCS12 -keystore $NewKeystore -alias $Alias `
        -keyalg RSA -keysize 4096 -validity $ValidDays -dname $Dname `
        -storepass $newPassword -keypass $newPassword | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE" }

    Write-Host ""
    Write-Host "Done. Next steps:"
    Write-Host "1. Create mobile/android/key.properties (git-ignored):"
    Write-Host "     storeFile=../release.jks"
    Write-Host "     keyAlias=$Alias"
    Write-Host "     storePassword=<the password you just typed>"
    Write-Host "     keyPassword=<the same password>"
    Write-Host "2. Build from mobile/: flutter build apk --release --split-per-abi"
    Write-Host "3. Back up release.jks and its password safely outside the repository."
    exit 0
}

if (-not (Test-Path $Keystore)) { throw "No old keystore at $Keystore." }
$apksignerPath = Resolve-Apksigner

if ($OldPassword) {
    $oldPassword = $OldPassword
} else {
    $oldPassword = Read-Host "Password of the debug keystore [$Keystore] (Enter for the default)"
    if ([string]::IsNullOrEmpty($oldPassword)) { $oldPassword = "android" }
}

Write-Host "Creating $NewKeystore ..."
& $keytoolPath -genkeypair -v -storetype PKCS12 -keystore $NewKeystore -alias $Alias `
    -keyalg RSA -keysize 4096 -validity $ValidDays -dname $Dname `
    -storepass $newPassword -keypass $newPassword | Out-Host
if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE" }

Write-Host "Building the rotation lineage $Lineage ..."
& $apksignerPath rotate --out $Lineage `
    --old-signer --ks $Keystore --ks-pass "pass:$oldPassword" --ks-key-alias androiddebugkey `
    --new-signer --ks $NewKeystore --ks-pass "pass:$newPassword" --ks-key-alias $Alias | Out-Host
if ($LASTEXITCODE -ne 0) { throw "apksigner rotate failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "1. Create mobile/android/key.properties (git-ignored):"
Write-Host "     storeFile=../release.jks"
Write-Host "     keyAlias=$Alias"
Write-Host "     storePassword=<the password you just typed>"
Write-Host "     keyPassword=<the same password>"
Write-Host "2. Build: flutter build apk --release --split-per-abi"
Write-Host "3. Re-sign that APK so the lineage travels with it (old signer first, then --next-signer):"
Write-Host "     apksigner sign --ks %USERPROFILE%\.android\debug.keystore --ks-pass pass:android --ks-key-alias androiddebugkey"
Write-Host "       --next-signer --ks android\release.jks --ks-pass pass:<new> --ks-key-alias $Alias"
Write-Host "       --lineage android\lineage.bin --in app-release.apk --out app-release-rotated.apk"
Write-Host "4. Verify both signers: apksigner verify --min-sdk-version 24 --print-certs app-release-rotated.apk"
Write-Host ""
Write-Host "Keep release.jks and lineage.bin backed up: together they are the app identity."
