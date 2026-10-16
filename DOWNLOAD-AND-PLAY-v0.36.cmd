@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0Get-OfflineDAoC.ps1" (
  echo Get-OfflineDAoC.ps1 is missing. Unzip the whole downloader zip from the release page, then retry.
  pause
  exit /b 1
)
echo Offline DAoC 0.36 - classic classes only, no custom class
echo.
echo This downloads the complete game, about 5 GB in checked parts, into a NEW
echo folder called playable-v0.36 next to this file. It never overwrites an
echo existing game and never starts anything by itself.
echo Allow about 20 GB of free disk space.
echo.
echo Before playing, turn on the Windows feature ".NET Framework 3.5" - see
echo READ ME FIRST.txt in the new folder.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-OfflineDAoC.ps1" -ReleaseVersion 0.36 -Destination "%~dp0playable-v0.36"
if errorlevel 1 goto failed
echo.
echo Done. Open the playable-v0.36 folder, read READ ME FIRST.txt, and run START OFFLINE DAOC.cmd.
pause
exit /b 0

:failed
echo.
echo The download did not finish. Run this file again to continue; finished parts are kept.
pause
exit /b 1
