@echo off
rem ============================================================================
rem  Nova Launcher - Portable Launcher
rem  Author : Tony
rem  Created: 2026-09-11
rem  Updated: 2026-09-14
rem  Desc   : Launch NovaLauncher.ps1 in hidden PowerShell window.
rem           The PS1 script creates a borderless WebView2 window as UI.
rem           Host exits automatically 25s after window closes.
rem  Note   : Keep this file ASCII (no Chinese chars) for max compatibility.
rem ============================================================================
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [ERROR] powershell.exe not found. Windows PowerShell 5.1+ required.
  pause
  exit /b 1
)

start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0data\NovaLauncher.ps1" %*
exit /b 0
