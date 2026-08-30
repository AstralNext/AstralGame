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
// 如果不关闭，正在打开的 exe/dll 会被锁住，安装程序无法覆盖文件。
// ======================================================================
procedure KillAstralGameProcesses(Force: Boolean);
var
  WM_CLOSE: Cardinal;
  Wnd: HWND;
  Pid: Cardinal;
  ResultCode: Integer;
  Retries: Integer;
begin
  WM_CLOSE := 16;

  // 1) 第一步：找到所有主窗口并发送 WM_CLOSE（温和关闭，Flutter 有机会保存数据）
  Wnd := FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Astral Game');
  if Wnd <> 0 then
  begin
    GetWindowThreadProcessId(Wnd, Pid);
    PostMessage(Wnd, WM_CLOSE, 0, 0);
    // 最多等 5 秒让进程自然退出
    for Retries := 0 to 25 do
    begin
      if not IsProcessRunning(Pid) then break;
      Sleep(200);
    end;
  end;

  // 2) 兜底：用 wmic/windows 工具搜索所有名为 astral_game.exe 的进程，
  //    如果 5 秒后还活着，就强制 taskkill /F（或第一次 Force=true 直接强杀）。
  if Force then
  begin
    Exec('taskkill.exe',
         '/F /IM astral_game.exe /T',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end
  else
  begin
    // 不 Force 也检查是否还活着，活着就 taskkill /F
    if FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Astral Game') <> 0 then
    begin
      Exec('taskkill.exe',
           '/F /IM astral_game.exe /T',
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end
    else
    begin
      // 窗口关了但进程可能还在（P2P isolate），再用 tasklist 兜底
      Exec('taskkill.exe',
           '/IM astral_game.exe /T',
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1500);
      Exec('taskkill.exe',
           '/F /IM astral_game.exe /T',
           '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;

  Sleep(500);
end;

function IsProcessRunning(Pid: Cardinal): Boolean;
var
  Handle: THandle;
begin
  Result := False;
  if Pid = 0 then exit;
  Handle := OpenProcess(STANDARD_RIGHTS_READ or PROCESS_QUERY_INFORMATION or SYNCHRONIZE, False, Pid);
  if Handle <> 0 then
  begin
    Result := WaitForSingleObject(Handle, 0) = WAIT_TIMEOUT;
    CloseHandle(Handle);
  end;
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
  // 卸载前也关闭正在运行的进程
  KillAstralGameProcesses(True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  // 在真正复制文件之前再最后杀一次（用户可能在安装向导过程中又把程序打开了）
  if CurStep = ssInstall then
  begin
    KillAstralGameProcesses(False);
  end;
end;
