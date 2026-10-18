@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0..\Get-OfflineDAoC.ps1" (
  echo Get-OfflineDAoC.ps1 is missing. Unzip the whole downloader zip from the release page, then retry.
  pause
  exit /b 1
)
echo Offline DAoC 0.36c - the game with BOTH clients: the original client and
echo the new client. Both play the same game, account and bots.
echo.
echo Already have Offline DAoC 0.36b or 0.36? Close this window and use
echo ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd instead.
echo.
echo Which game do you want with the new client?
echo   1 = 0.36b, with the custom Sluaghbinder class (recommended)
echo   2 = 0.36, the original Classic + Shrouded Isles classes only
choice /c 12 /n /m "Press 1 or 2: "
if errorlevel 2 (
  set "EDITION=0.36"
  set "FOLDER=playable-v0.36c-classic"
  set "CLASSIC=-Classic"
) else (
  set "EDITION=0.36b"
  set "FOLDER=playable-v0.36c"
  set "CLASSIC="
)
echo.
echo This downloads, into a NEW folder called %FOLDER% next to this file:
echo   1. the complete %EDITION% game, about 5 GB
echo   2. the new client, about 30 GB in parts
echo Every part is checked before it is used. It never overwrites an existing
echo game and never starts anything by itself.
echo Allow about 60 GB of free disk space while it installs.
echo If it stops, run this file again and press the same number: it continues
echo where it stopped.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Get-OfflineDAoC.ps1" -ReleaseVersion 0.36c %CLASSIC% -Destination "%~dp0%FOLDER%"
if errorlevel 1 goto failed
echo.
echo Done. Open the %FOLDER% folder and read READ ME - NEW CLIENT.txt.
echo   START OFFLINE DAOC - NEW CLIENT.cmd   plays with the new client
echo   START OFFLINE DAOC.cmd               plays with the original client
echo Before playing with the original client, turn on the Windows feature
echo ".NET Framework 3.5" - see READ ME FIRST.txt there.
pause
exit /b 0

:failed
echo.
echo The download did not finish. Run this file again (and press the same number)
echo to continue where it stopped.
pause
exit /b 1
