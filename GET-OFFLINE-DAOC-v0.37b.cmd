@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0Get-OfflineDAoC.ps1" (
  echo Get-OfflineDAoC.ps1 is missing. Unzip the whole downloader zip from the release page, then retry.
  pause
  exit /b 1
)
echo Offline DAoC 0.37b - with the custom Sluaghbinder class
echo.
echo   1 = Update my game. You already have Offline DAoC 0.36, 0.36b or 0.36c:
echo       a window opens, choose your game folder. Only the update is downloaded
echo       (much smaller than the game). Your account, characters, bots and
echo       settings stay as they are. If you also have the new client, it is
echo       updated too.
echo   2 = New install. You don't have the game yet: it downloads the complete
echo       game (about 5 GB) into a new folder next to this file and updates it.
echo.
choice /c 12 /n /m "Press 1 or 2: "
if errorlevel 2 goto newinstall
echo.
echo Close the Offline DAoC launcher and the game first.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-OfflineDAoC.ps1" -ReleaseVersion 0.37b -Update pick
if errorlevel 1 goto failed
goto done

:newinstall
echo.
echo This downloads, into a NEW folder called playable-v0.37b next to this file,
echo the complete game (about 5 GB in checked parts) and then the update. It never
echo overwrites an existing game. Allow about 20 GB of free disk space.
echo If it stops, run this file again and press 2: it continues where it stopped.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-OfflineDAoC.ps1" -ReleaseVersion 0.37b -Destination "%~dp0playable-v0.37b"
if errorlevel 1 goto failed
echo.
echo Open the playable-v0.37b folder, read READ ME FIRST.txt, and run START OFFLINE DAOC.cmd.
echo Before playing, turn on the Windows feature ".NET Framework 3.5" - see READ ME FIRST.txt.

:done
echo.
pause
exit /b 0

:failed
echo.
echo It did not finish. Run this file again to continue; finished downloads are kept.
pause
exit /b 1
