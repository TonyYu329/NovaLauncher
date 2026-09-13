@echo off
chcp 65001 >nul 2>&1
rem ============================================================================
rem  Nova Launcher - 绿色版入口
rem  1 首次创建人   ：Tony
rem  2 首次创建时间 ：2026-09-11 16:03:30
rem  3 功能简介     ：双击启动本地宿主（NovaLauncher.ps1），宿主再以 --app
rem                   模式拉起无边框浏览器窗口作为 Nova Launcher 界面。
rem                   关闭界面窗口后，宿主会在 25 秒内自动退出，无残留进程。
rem  4 最后修改人   ：Tony
rem  5 最后修改时间 ：2026-09-11 16:03:30
rem
rem  注意：本文件必须保持 UTF-8 无 BOM（cmd.exe 不识别 BOM，会报错）。
rem        chcp 65001 必须在中文文本出现之前执行。
rem ============================================================================
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [错误] 未找到 powershell.exe，本工具需要 Windows PowerShell 5.1 或更高版本。
  pause
  exit /b 1
)

echo 正在启动 Nova Launcher ...
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0data\NovaLauncher.ps1" %*
exit /b 0
