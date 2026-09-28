@echo off
rem Double-click me on the client PC: installs WholeFlow as a Windows service
rem (auto-start at boot, runs hidden). Needs wholeflow.exe in this folder.
rem Pass -Uninstall to remove it, e.g.:  Install-WholeFlow.cmd -Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-WholeFlow.ps1" %*
