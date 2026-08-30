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
// ======================================================================
// 安装/卸载前：强制关闭正在运行的 astral_game.exe 进程。
// 用 tasklist + taskkill，避免依赖 Win32 API（Inno Setup 没内置）。
// ======================================================================
function IsAstralGameRunning(): Boolean;
var
  ResultCode: Integer;
  CmdLine: String;
  Output: String;
begin
  // tasklist /FI 过滤进程名；如果找得到会输出多行信息，找不到就只输出表头
  CmdLine := '/C tasklist /FI "IMAGENAME eq astral_game.exe" /NH 2>nul | findstr /I /C:"astral_game.exe" >nul';
  Result := Exec('cmd.exe', CmdLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if Result then
    Result := (ResultCode = 0); // findstr 找到 = 0
end;

procedure KillAstralGameProcesses(Force: Boolean);
var
  ResultCode: Integer;
  Retries: Integer;
begin
  // 1) 温和关闭：WM_QUERYENDSESSION + WM_CLOSE 级别——用 taskkill 不带 /F
  //    这样 Flutter 有机会保存 bookmark、断开 P2P、写 SharedPreferences
  if not Force then
  begin
    Exec('taskkill.exe',
         '/T /IM astral_game.exe',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // 最多等 5 秒确认进程退出
    for Retries := 0 to 10 do
    begin
      if not IsAstralGameRunning() then break;
      Sleep(500);
    end;
  end;

  // 2) 还活着或者 Force=true 直接强杀
  if Force or IsAstralGameRunning() then
  begin
    Exec('taskkill.exe',
         '/F /T /IM astral_game.exe',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
    // 再兜底一次：如果用户启动了多开或者有残留 zombie，用 PID 通配杀一遍
    Exec('cmd.exe',
         '/C wmic process where name="astral_game.exe" call terminate 2>nul >nul',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;

  Sleep(300);
end;

function InitializeSetup(): Boolean;
begin
  Result := IsAdminInstallMode;
  if not Result then
  begin
    MsgBox('Astral Game 安装程序必须以管理员身份运行。', mbError, MB_OK);
    exit;
  end;

  // 安装前先关闭正在运行的进程，避免文件占用无法覆盖
  KillAstralGameProcesses(False);
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  // 卸载前直接强杀
  KillAstralGameProcesses(True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // 真正复制文件之前再最后杀一次（用户可能在安装向导期间又把软件打开了）
  if CurStep = ssInstall then
  begin
    KillAstralGameProcesses(False);
  end;
end;
