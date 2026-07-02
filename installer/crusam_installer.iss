; ============================================================================
; CruSam Windows Installer (Inno Setup 6)
; ============================================================================
; Per-user installer for CruSam. Packages the Flutter Release build output
; (crusam.exe + engine DLLs + data\) together with updater.exe.
;
; Build-time defines (passed via ISCC's /D switch):
;
;   MyAppVersion  Required for a real release build. e.g.:
;                   iscc crusam_installer.iss /DMyAppVersion=2.0.0
;                 Falls back to "0.0.0" if omitted, so the script can still
;                 be opened/compiled manually in the Inno Setup IDE.
;
;   ReleaseDir    Optional. Absolute path to the Flutter Release output
;                 folder (the one containing crusam.exe). Passed by
;                 build_release.ps1, which auto-detects the correct path
;                 for the Flutter version in use. Falls back to the
;                 conventional relative path below if omitted.
;
; NOTE ON SLASHES: path values passed to #define / /D go through Inno
; Setup's preprocessor, which applies C-style string escaping (\n, \t, \xHH,
; ...). A literal Windows path containing e.g. "\x64" can be silently
; corrupted by that escape processing. Forward slashes avoid the problem
; entirely and Windows/Inno resolve them identically to backslashes, so
; every path define below uses "/" rather than "\".
; ============================================================================

#define MyAppName "CruSam"
#define MyAppPublisher "CruciaTos"
#define MyAppURL "https://github.com/CruciaTos/CruSam"
#define MyAppExeName "crusam.exe"
#define MyAppId "{09861913-DB97-4C6E-AFE4-EF885545D6F8}"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef ReleaseDir
  #define ReleaseDir "../crusam/build/windows/x64/runner/Release"
#endif

#define AppIconFile "../crusam/windows/runner/resources/app_icon.ico"

[Setup]
; Permanent AppId — do not change. This is what lets Setup recognize an
; existing install (same registry key) and perform an in-place upgrade
; instead of a side-by-side install.
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} Setup

; ---- Per-user install, no admin rights, no UAC prompt -----------------
DefaultDirName={localappdata}\Programs\CruSam
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

; ---- In-place upgrade support ------------------------------------------
; AppId is fixed, so Setup finds any previous install of this AppId via the
; registry and reuses its directory/group automatically. These are Inno's
; defaults but are stated explicitly since in-place upgrade is a hard
; requirement here.
UsePreviousAppDir=yes
UsePreviousGroup=yes
UpdateUninstallLogAppName=yes

; ---- Native "close running app" support (Inno Setup 6 / Restart Manager)
; Setup detects crusam.exe / updater.exe if running and closes them (with a
; prompt in interactive mode, silently under /VERYSILENT) before copying
; files over them. No custom process-killing code needed.
CloseApplications=yes
CloseApplicationsFilter=crusam.exe,updater.exe
; Restart Manager restarting the app on its own would race with, and could
; double-launch alongside, the explicit "Launch CruSam" checkbox below —
; so relaunching is left entirely to that checkbox.
RestartApplications=no

; ---- Output ---------------------------------------------------------------
OutputDir=Output
OutputBaseFilename=CruSam-Setup-{#MyAppVersion}
SetupIconFile={#AppIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; 64-bit only — matches the Flutter Windows x64 build output. "x64" is
; recognized by every Inno Setup 6.x release; if you're on Inno Setup 6.3+
; and want native ARM64 Windows support via x64 emulation, both values here
; can be changed to "x64compatible" instead.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; Flutter's Windows desktop embedder targets Windows 10 or later.
MinVersion=10.0

; /VERYSILENT, /SUPPRESSMSGBOXES, /NORESTART and /SP- are all handled
; natively by Setup's command-line parsing — nothing further to configure
; for them. No [Code] section is used in this script, so there is no custom
; UI that could block a silent run.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; Entire Release output tree: crusam.exe, the Flutter engine DLLs, the
; data\ folder, and updater.exe (copied into ReleaseDir by
; build_release.ps1 before this script runs).
;
; This is the ONLY [Files] entry in the script, and ReleaseDir always
; resolves to the build output under crusam\build\... — never to any
; %AppData% path. Per-user data (aarti.db etc., resolved via AppPaths)
; lives under {userappdata}\com.cructiatus\... and must never appear here.
Source: "{#ReleaseDir}/*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Recursively remove the install directory itself on uninstall (engine
; DLLs, updater.exe, and any runtime files the app writes inside its own
; folder — e.g. updater.log, the temporary installed_version.txt fallback —
; none of which are tracked individually by [Files]).
;
; This is safe specifically because {app} is {localappdata}\Programs\CruSam,
; a directory tree entirely separate from the %AppData%\Roaming user-data
; path. Nothing in this script ever references an %AppData% path, so
; nothing under it can ever be deleted by this installer or its uninstaller.
Type: filesandordirs; Name: "{app}"
