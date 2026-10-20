@echo off
rem LibreTV double-click launcher (hidden PowerShell)
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0start-LibreTV.ps1"
