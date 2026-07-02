<#
.SYNOPSIS
    CruSam Windows release pipeline.

.DESCRIPTION
    Implements the release procedure from crusam/RELEASE.md and
    crusam/UPDATE_SYSTEM_README.md end-to-end:

      1. Read the version from crusam/pubspec.yaml (single source of truth).
      2. flutter clean
      3. flutter pub get
      4. flutter build windows --release
      5. Verify crusam.exe's embedded file version matches pubspec.yaml
         (automates the manual check RELEASE.md calls out; aborts rather
         than packaging a stale build).
      6. Build updater.exe (dart compile exe) and copy it next to crusam.exe.
      7. Compile installer/crusam_installer.iss with Inno Setup (ISCC.exe),
         producing installer/Output/CruSam-Setup-<version>.exe.

    Run this from anywhere; all paths are resolved relative to this script's
    location (installer/), which is expected to be a sibling of crusam/ and
    updater/ at the repo root.

.PARAMETER SkipVerify
    Skip the embedded-file-version verification step. Not recommended —
    only useful for quick local iteration.

.PARAMETER IsccPath
    Path to ISCC.exe (the Inno Setup 6 command-line compiler). If omitted,
    the script looks on PATH, then the two standard install locations.

.EXAMPLE
    .\installer\build_release.ps1

.EXAMPLE
    .\installer\build_release.ps1 -IsccPath "D:\Tools\Inno Setup 6\ISCC.exe"
#>

[CmdletBinding()]
param(
    [switch]$SkipVerify,
    [string]$IsccPath
)

$ErrorActionPreference = 'Stop'

# ── Paths ────────────────────────────────────────────────────────────────
$InstallerDir = $PSScriptRoot
$RepoRoot     = Split-Path -Parent $InstallerDir
$CrusamDir    = Join-Path $RepoRoot 'crusam'
$UpdaterDir   = Join-Path $RepoRoot 'updater'
$PubspecPath  = Join-Path $CrusamDir 'pubspec.yaml'
$IssPath      = Join-Path $InstallerDir 'crusam_installer.iss'
$OutputDir    = Join-Path $InstallerDir 'Output'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

# ── 1. Read version from pubspec.yaml ───────────────────────────────────
Write-Step "Reading version from pubspec.yaml"

if (-not (Test-Path $PubspecPath)) {
    Fail "pubspec.yaml not found at $PubspecPath"
}

# Top-level "version:" key only (unindented) — avoids matching any nested
# "version" key that might appear under dependencies, etc.
$versionMatch = Select-String -Path $PubspecPath -Pattern '^version:\s*(\S+)' |
    Select-Object -First 1

if (-not $versionMatch) {
    Fail "Could not find a top-level 'version:' line in $PubspecPath"
}

$fullVersion = $versionMatch.Matches[0].Groups[1].Value.Trim()   # e.g. "2.0.0+1"
$versionOnly = $fullVersion.Split('+')[0]                        # e.g. "2.0.0" – only for installer filename

if ($versionOnly -notmatch '^\d+\.\d+\.\d+$') {
    Fail "Unexpected version format '$fullVersion' in pubspec.yaml (expected MAJOR.MINOR.PATCH[+BUILD])"
}

Write-Host "pubspec.yaml version : $fullVersion"
Write-Host "Installer version    : $versionOnly"

# ── 2-4. Clean Flutter Windows release build ────────────────────────────
Push-Location $CrusamDir
try {
    Write-Step "flutter clean"
    flutter clean
    if ($LASTEXITCODE -ne 0) { Fail "flutter clean failed" }

    Write-Step "flutter pub get"
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed" }

    Write-Step "flutter build windows --release"
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { Fail "flutter build windows --release failed" }
} finally {
    Pop-Location
}

# ── Locate the Release output folder ─────────────────────────────────────
# Flutter has used two different layouts across versions (see RELEASE.md);
# try both rather than hardcoding one.
$candidateReleaseDirs = @(
    (Join-Path $CrusamDir 'build\windows\x64\runner\Release'),
    (Join-Path $CrusamDir 'build\windows\runner\Release')
)
$ReleaseDir = $candidateReleaseDirs |
    Where-Object { Test-Path (Join-Path $_ 'crusam.exe') } |
    Select-Object -First 1

if (-not $ReleaseDir) {
    $triedPaths = $candidateReleaseDirs -join "`n  "
    Fail "Could not find crusam.exe under either known Release output path:`n  $triedPaths"
}

$CrusamExePath = Join-Path $ReleaseDir 'crusam.exe'
Write-Host "Release output        : $ReleaseDir"

# ── 5. Verify the embedded file version matches pubspec.yaml ────────────
if (-not $SkipVerify) {
    Write-Step "Verifying crusam.exe embedded version"

    $fileVersion = (Get-Item $CrusamExePath).VersionInfo.FileVersion
    if (-not $fileVersion) {
        Fail "Could not read FileVersion from $CrusamExePath"
    }

    # Compare directly to the pubspec version string (Flutter on Windows
    # embeds the version as-is, including the '+' build number suffix).
    if ($fileVersion -ne $fullVersion) {
        Fail "crusam.exe's embedded File version ($fileVersion) does not match pubspec.yaml ($fullVersion). This is the stale-build problem RELEASE.md warns about -- do not package this build. Re-run and confirm 'flutter clean' actually removed build/ and windows/flutter/ephemeral/ before rebuilding."
    }

    Write-Host "Embedded version matches pubspec.yaml: $fileVersion"
} else {
    Write-Host "Skipping embedded version verification (-SkipVerify)." -ForegroundColor Yellow
}

# ── 6. Build updater.exe and copy it next to crusam.exe ─────────────────
Write-Step "Building updater.exe"

Push-Location $UpdaterDir
try {
    dart pub get
    if ($LASTEXITCODE -ne 0) { Fail "dart pub get (updater) failed" }

    dart compile exe bin\main.dart -o updater.exe
    if ($LASTEXITCODE -ne 0) { Fail "dart compile exe (updater) failed" }
} finally {
    Pop-Location
}

Copy-Item -Path (Join-Path $UpdaterDir 'updater.exe') -Destination (Join-Path $ReleaseDir 'updater.exe') -Force
Write-Host "updater.exe copied to $ReleaseDir"

# ── Locate ISCC.exe (Inno Setup 6 command-line compiler) ────────────────
if (-not $IsccPath) {
    $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($onPath) {
        $IsccPath = $onPath.Source
    } else {
        $wellKnownPaths = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
        )
        $IsccPath = $wellKnownPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}

if (-not $IsccPath -or -not (Test-Path $IsccPath)) {
    Fail "Could not find ISCC.exe. Install Inno Setup 6 (https://jrsoftware.org/isinfo.php) or pass -IsccPath explicitly."
}
Write-Host "Inno Setup compiler    : $IsccPath"

# ── 7. Build the installer ───────────────────────────────────────────────
Write-Step "Building installer with Inno Setup"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Inno Setup's preprocessor applies C-style string escaping to /D values
# (\n, \t, \xHH, ...), which can silently corrupt a plain Windows path
# containing a sequence like "\x64". Passing the path with forward slashes
# instead sidesteps the problem entirely -- Inno resolves "/" the same as
# "\" when reading files.
$ReleaseDirForIscc = $ReleaseDir -replace '\\', '/'

$isccArgs = @(
    "/DMyAppVersion=$versionOnly",
    "/DReleaseDir=$ReleaseDirForIscc",
    "/O$OutputDir",
    $IssPath
)

& $IsccPath @isccArgs
if ($LASTEXITCODE -ne 0) { Fail "Inno Setup compilation failed" }

$installerPath = Join-Path $OutputDir "CruSam-Setup-$versionOnly.exe"
if (-not (Test-Path $installerPath)) {
    Fail "Expected installer not found at $installerPath after compilation"
}

Write-Step "Done"
Write-Host "Installer produced: $installerPath" -ForegroundColor Green