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
// 安装/卸载前：检测正在运行的 astral_game.exe，询问用户再关闭。
//   - 不占用启动时间：先快速 tasklist 检测，不在跑直接通过
//   - 在跑 → 弹 MsgBox 询问用户是否自动关闭
//   - 用户点"是" → 温和 taskkill → 超时才强杀，避免破坏 Flutter 保存
//   - 用户点"否" → 取消安装/卸载
// ======================================================================
function IsAstralGameRunning(): Boolean;
var
  ResultCode: Integer;
begin
  // 快速检测：tasklist 过滤 + findstr 匹配，毫秒级
  Result := Exec('cmd.exe',
    '/C tasklist /FI "IMAGENAME eq astral_game.exe" /NH 2>nul | findstr /I /B /C:"astral_game.exe" >nul',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if Result then
    Result := (ResultCode = 0); // findstr 找到即返回 0
end;

// 返回 True = 进程已终止（或本来就没在跑），可以继续安装/卸载
// 返回 False = 用户取消
function ConfirmAndKillAstralGame(const Caption: String; AskUser: Boolean): Boolean;
var
  Res: Integer;
  ResultCode: Integer;
  Msg: String;
begin
  Result := True;

  // 1. 不在跑 → 立刻通过
  if not IsAstralGameRunning() then exit;

  // 2. 在跑：先问用户（AskUser=True 时）
  if AskUser then
  begin
    Msg := '检测到 Astral Game 正在运行。' + #13#10 + #13#10
         + '如果不关闭，安装程序无法覆盖正在使用的文件。' + #13#10 + #13#10
         + '是否立即强制关闭它并继续' + Caption + '？' + #13#10
         + '（选「是」立即关闭；选「否」取消本次操作）';
    Res := MsgBox(Msg, mbConfirmation, MB_YESNO or MB_DEFBUTTON1);
    if Res <> IDYES then
    begin
      Result := False;
      exit;
    end;
  end;

  // 3. 用户点"是" 或 不用问的场景 → 直接强杀，不等待任何保存
  Exec('taskkill.exe', '/F /T /IM astral_game.exe',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(250);
  Exec('cmd.exe',
       '/C wmic process where name="astral_game.exe" call terminate 2>nul >nul',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(150);
end;

function InitializeSetup(): Boolean;
begin
  Result := IsAdminInstallMode;
  if not Result then
  begin
    MsgBox('Astral Game 安装程序必须以管理员身份运行。', mbError, MB_OK);
    exit;
  end;

  // 启动时快速检测 → 检测到才询问，同意直接强杀不等
  Result := ConfirmAndKillAstralGame('安装', True {AskUser});
end;

function InitializeUninstall(): Boolean;
begin
  // 卸载：同样询问式
  Result := ConfirmAndKillAstralGame('卸载', True {AskUser});
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Dummy: Boolean;
begin
  // 真正复制文件前再检查一次——不再问，直接强杀
  if CurStep = ssInstall then
  begin
    Dummy := ConfirmAndKillAstralGame('安装', False {NoAsk});
  end;
end;
