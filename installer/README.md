# CruSam Installer & Release Automation

This folder contains the Phase 5 packaging pipeline: the Inno Setup
installer script and the PowerShell script that drives the full release
build. For the app-side update mechanism (how `crusam.exe` discovers and
downloads releases), see `../crusam/RELEASE.md` and
`../crusam/UPDATE_SYSTEM_README.md` — this folder only covers turning a
Release build into `CruSam-Setup-<version>.exe`.

## Files

| File                    | Purpose                                                       |
|--------------------------|----------------------------------------------------------------|
| `crusam_installer.iss`  | Inno Setup 6 script. Defines the per-user installer.          |
| `build_release.ps1`     | End-to-end release pipeline (build → verify → package).       |

## Prerequisites

- Flutter SDK (with Windows desktop support enabled) and Dart SDK on `PATH`.
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) installed. `build_release.ps1`
  looks for `ISCC.exe` on `PATH`, then under the two standard
  `Program Files` locations. If it's installed somewhere else, pass
  `-IsccPath`.
- Windows, since this packages a Windows desktop build.

## Usage

From a PowerShell prompt, from anywhere in the repo:

```powershell
.\installer\build_release.ps1
```

This runs the full pipeline described in `crusam/RELEASE.md`:

1. Reads `version:` from `crusam/pubspec.yaml` (e.g. `2.0.0+1` → installer
   version `2.0.0`).
2. `flutter clean`
3. `flutter pub get`
4. `flutter build windows --release`
5. Verifies the built `crusam.exe`'s embedded File version matches
   `pubspec.yaml` — aborts if they disagree instead of packaging a stale
   build (this automates the manual Explorer-properties check
   `RELEASE.md` documents).
6. Builds `updater.exe` (`dart compile exe`) and copies it next to
   `crusam.exe`.
7. Runs Inno Setup against `crusam_installer.iss`, producing:

   ```
   installer\Output\CruSam-Setup-<version>.exe
   ```

Upload that file as-is to the GitHub release tagged `v<version>` — the
filename convention is what the in-app updater matches against (see
`RELEASE.md`, "How the app discovers updates").

### Options

```powershell
# Skip the embedded-version check (fast local iteration only — do not use
# for a build you intend to publish)
.\installer\build_release.ps1 -SkipVerify

# Point at a non-standard Inno Setup install location
.\installer\build_release.ps1 -IsccPath "D:\Tools\Inno Setup 6\ISCC.exe"
```

### Building the installer only (build already done)

If you've already run steps 1–6 yourself and just want to (re)compile the
installer:

```powershell
iscc installer\crusam_installer.iss /DMyAppVersion=2.0.0
```

This uses the script's default `ReleaseDir`
(`crusam\build\windows\x64\runner\Release`, relative to `installer\`), so
`updater.exe` must already be sitting next to `crusam.exe` there. If your
Flutter build landed under the older `crusam\build\windows\runner\Release`
path instead, override it explicitly:

```powershell
iscc installer\crusam_installer.iss /DMyAppVersion=2.0.0 /DReleaseDir=../crusam/build/windows/runner/Release
```

(Use forward slashes in `/DReleaseDir` — see the comment at the top of
`crusam_installer.iss` for why.)

## What the installer does and does not touch

- Installs per-user to `{localappdata}\Programs\CruSam` — no admin rights,
  no UAC prompt.
- Supports in-place upgrades: the AppId is fixed
  (`09861913-DB97-4C6E-AFE4-EF885545D6F8`), so re-running a newer installer
  finds and overwrites the existing install rather than creating a second
  copy. Do not change this AppId.
- Closes a running `crusam.exe` / `updater.exe` automatically before
  copying files (Inno Setup's native Restart Manager integration —
  `CloseApplications`), rather than any custom process-killing code.
- Never references, packages, or deletes anything under
  `%AppData%\Roaming\com.cructiatus\...` (where `aarti.db` and other
  persistent user data live, per Phase 1). The installer's own uninstall
  step only ever removes `{localappdata}\Programs\CruSam` — a completely
  separate directory tree.
- Supports the standard silent-install switches out of the box:
  `/VERYSILENT`, `/SUPPRESSMSGBOXES`, `/NORESTART`, `/SP-`.

## Output

`installer\Output\` holds compiled installers and is git-ignored; it's
build output, not source.
