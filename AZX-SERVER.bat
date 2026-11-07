@echo off
setlocal
cd /d "%~dp0"
title AZX SERVER
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher\manager.ps1"
if errorlevel 1 pause
endlocal
