@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0Get-OfflineDAoC.ps1" (
  echo Get-OfflineDAoC.ps1 is missing. Unzip the whole downloader zip from the release page, then retry.
  pause
  exit /b 1
)
echo Offline DAoC 0.36c - add the new client to your Offline DAoC 0.36b or 0.36 game
echo.
echo A window opens: choose your game folder, the one with START OFFLINE DAOC.cmd
echo in it. The new client goes into a new-client folder there. Your account,
echo characters, bots and settings are not changed, and both clients will play
echo them. On a 0.36 game the new client offers the classic classes only, just
echo like the original client.
echo.
echo The new client is about 30 GB in checked parts; allow about 40 GB of free
echo disk space while it installs. If it stops, run this file again.
echo Close the launcher and the game first.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-OfflineDAoC.ps1" -ReleaseVersion 0.36c -AddTo pick
if errorlevel 1 goto failed
echo.
echo Done. In your game folder, START OFFLINE DAOC - NEW CLIENT.cmd plays with the
echo new client; START OFFLINE DAOC.cmd still plays with the original client.
pause
exit /b 0

:failed
echo.
echo The new client was not installed completely. Run this file again to continue.
pause
exit /b 1
