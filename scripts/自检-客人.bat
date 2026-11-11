@echo off
setlocal EnableDelayedExpansion
title Astral 自检 - 客人（零点击）

rem 双击即用：自动搜房/加入、写报告、自己退出。
rem 需要管理员（Steam 虚拟网卡），未提权时自动请求 UAC。
rem 也可以带参数双击：本脚本 109775243733016710

net session >nul 2>&1
if errorlevel 1 (
  echo 正在请求管理员权限……
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

tasklist /FI "IMAGENAME eq astral_game.exe" 2>nul | find /I "astral_game.exe" >nul
if not errorlevel 1 (
  echo 检测到 Astral Game 已在运行，请先从托盘完全退出后再双击本脚本。
  pause
  exit /b 1
)

set "EXE="
if exist "%~dp0..\build\windows\x64\runner\Release\astral_game.exe" set "EXE=%~dp0..\build\windows\x64\runner\Release\astral_game.exe"
if not defined EXE if exist "%~dp0astral_game.exe" set "EXE=%~dp0astral_game.exe"
if not defined EXE if exist "%ProgramFiles%\Astral Game\astral_game.exe" set "EXE=%ProgramFiles%\Astral Game\astral_game.exe"
if not defined EXE (
  echo 找不到 astral_game.exe：请把本脚本放到程序目录，或仓库的 scripts\ 目录。
  pause
  exit /b 1
)

set "LOBBY=%~1"
if not defined LOBBY echo 房主报告第一段「大厅 id」就是房间号（纯数字）。
if not defined LOBBY set /p "LOBBY=直接回车 = 自动搜房；粘贴大厅 id 再回车 = 直达该房："
if defined LOBBY set "LOBBY=%LOBBY: =%"

set "ARGS=--selftest-guest"
if defined LOBBY set "ARGS=%ARGS% --lobby=%LOBBY%"

set "ASTRAL_STEAM_DEBUG=1"
set "ASTRAL_SELFTEST_WAIT_SECS=120"

echo.
echo 零点击自检（客人）：启动后自动搜房或直达大厅，校验握手后自己退出。
echo 跑完桌面会出现 astral-steam-selftest-guest-时间戳.log。
echo 程序在后台运行，不会弹出窗口。
echo 引擎调试日志：%TEMP%\astral-steam-debug.log
echo 使用：%EXE%
echo 参数：%ARGS%
echo.

for %%I in ("%EXE%") do set "EXEDIR=%%~dpI"
pushd "%EXEDIR%"
start "" /wait "%EXE%" %ARGS%
set "RC=%ERRORLEVEL%"
popd

echo.
echo 自检已结束（退出码 %RC%：0=成功，2=未通过，3=启动失败）。
echo 报告在桌面：astral-steam-selftest-guest-时间戳.log
echo 把桌面新生成的报告发给对方。
ping -n 9 127.0.0.1 >nul
