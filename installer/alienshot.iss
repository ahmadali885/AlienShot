#define MyAppName "AlienShot"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "AlienWave"
#define MyAppExeName "AlienShot.exe"
; The app shipped as "Snaply" (snapgrab.exe) before the rename.
#define LegacyAppName "Snaply"
#define LegacyExeName "snapgrab.exe"

[Setup]
; Unchanged from the Snaply builds on purpose: same AppId means this installer
; upgrades an existing Snaply install instead of adding a second app.
AppId={{B6E1B6B0-6E2A-4A2C-9C1A-9B7B7A2D9F11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; Otherwise an upgrade would keep installing into the old "Snaply" folder and
; Start menu group.
UsePreviousAppDir=no
UsePreviousGroup=no
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=AlienShot-Setup
SetupIconFile=..\assets\images\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
; Explorer caches icons by path, so an update that swaps the exe's icon kept
; showing the old one on shortcuts. This makes Setup broadcast
; SHCNE_ASSOCCHANGED when it finishes, which flushes that cache.
ChangesAssociations=yes
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startupicon"; Description: "Start {#MyAppName} automatically when Windows starts"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Leftovers from the Snaply-era install: its folder and shortcuts point at
; snapgrab.exe, which no longer exists — the startup entry in particular would
; fail silently at every sign-in.
Type: filesandordirs; Name: "{autopf}\{#LegacyAppName}"
Type: filesandordirs; Name: "{autoprograms}\{#LegacyAppName}"
Type: files; Name: "{autodesktop}\{#LegacyAppName}.lnk"
Type: files; Name: "{userstartup}\{#LegacyAppName}.lnk"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// The app lives in the tray with no visible window, so Windows' Restart
// Manager can't shut it down and every locked file fails with "Access is
// denied" — and skipping those leaves a half-updated install. Close it (under
// either the current or the pre-rename exe name) before touching any file.
procedure CloseRunningApp;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName} /IM {#LegacyExeName}', '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(600);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseRunningApp;
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  CloseRunningApp;
  Result := True;
end;
