; Astral Game — Windows 安装包（Inno Setup 6）
; CI：由 .github/workflows/build.yml 中 windows 任务在 flutter build 后调用 ISCC。
; 本地：在仓库根目录执行 flutter build windows --release 后编译本脚本。
;
; 版本号：命令行覆盖，例如：
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\astral_game.iss /DMyAppVersion=1.0.0
;
; 输出文件名：astral-game-{MyAppVersion}-windows-x64-setup.exe

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "Astral Game"
#define MyAppPublisher "AstralNext"
#define MyAppExeName "astral_game.exe"
; 相对本 .iss 文件：installer\..\build\windows\x64\runner\Release
#define BuildOutput "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B2F8E4C1-9A3D-4E7B-8F1A-2C9D0E1F3A5B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={commonpf}\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
; 必须管理员（UAC）；不要设置 PrivilegesRequiredOverridesAllowed，以免降权安装。
PrivilegesRequired=admin
WizardStyle=modern
SolidCompression=yes
; 规范命名：astral-game-<semver>-windows-x64-setup.exe
OutputDir=..\release_installer
OutputBaseFilename=astral-game-{#MyAppVersion}-windows-x64-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildOutput}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{commonprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKLM; Subkey: "Software\Classes\astralgame"; ValueType: string; ValueName: ""; ValueData: "URL:Astral Game"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\astralgame"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\astralgame\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKLM; Subkey: "Software\Classes\astralgame\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
; 安装结束勾选「启动」时以管理员运行（与 exe manifest requireAdministrator 一致）。
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent shellexec; Verb: runas

[Code]
function InitializeSetup(): Boolean;
begin
  Result := IsAdminInstallMode;
  if not Result then
    MsgBox('Astral Game 安装程序必须以管理员身份运行。', mbError, MB_OK);
end;
