@echo off
setlocal EnableDelayedExpansion
title Astral 双机自检 - 房主

rem 双击即用。需要管理员（Steam 虚拟网卡），未提权时自动请求 UAC。

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

echo 启动程序（带调试标志，直接打开 Steam Tab）……
set "ASTRAL_STEAM_DEBUG=1"
set "ASTRAL_SELFTEST_WAIT_SECS=120"
echo 使用：%EXE%
for %%I in ("%EXE%") do set "EXEDIR=%%~dpI"
pushd "%EXEDIR%"
start "" "%EXE%" --steam-selftest
popd

echo.
echo 日志位置：
echo   引擎调试日志：%TEMP%\astral-steam-debug.log
echo   自检报告：桌面\astral-steam-selftest-host-时间戳.log（跑完自动生成）
echo.
echo 在 Steam Tab 点一次「自检：房主跑一遍」，把桌面上新生成的报告发给对方。
pause
