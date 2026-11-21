@echo off
REM Drag an MP3 or MP4 onto this file to send it to the NOVA6 screen.
if "%~1"=="" (
  echo Drag an MP3 or MP4 file onto send.bat
  pause & exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0send.ps1" "%~1"
echo.
pause
