@echo off
setlocal
cd /d "%~dp0"
title NOVA6 sender
if "%~1"=="" goto noargs
echo Sending: %~1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0send.ps1" "%~1"
goto done
:noargs
echo Drag an MP3 or MP4 file onto send.bat
:done
echo.
pause
