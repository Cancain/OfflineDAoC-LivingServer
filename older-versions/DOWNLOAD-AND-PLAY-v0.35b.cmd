@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0..\Get-OfflineDAoC.ps1" (
  echo Download Get-OfflineDAoC.ps1 from the same release into this folder first.
  pause
  exit /b 1
)
echo Offline DAoC 0.35b "Claude Takeover III" - with the custom Sluaghbinder class
echo.
echo This downloads the complete game (about 5 GB, in checked parts) into a NEW
echo folder called playable-v0.35b. It never overwrites an existing game and
echo never starts anything by itself. Allow about 20 GB of free disk space.
echo.
echo Before playing, turn on the Windows feature ".NET Framework 3.5" - see
echo READ ME FIRST.txt in the new folder.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Get-OfflineDAoC.ps1" -ReleaseVersion 0.35b -Destination "%~dp0playable-v0.35b"
if errorlevel 1 (
  echo.
  echo The download did not finish. Run this file again to continue; finished parts are kept.
  pause
  exit /b 1
)
echo.
echo Done. Open playable-v0.35b, read READ ME FIRST.txt, and run START OFFLINE DAOC.cmd.
pause
