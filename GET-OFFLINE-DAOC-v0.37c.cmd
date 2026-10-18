@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0Get-OfflineDAoC.ps1" (
  echo Get-OfflineDAoC.ps1 is missing. Unzip the whole downloader zip from the release page, then retry.
  pause
  exit /b 1
)
echo Offline DAoC 0.37c (BETA) - the game with BOTH clients: the original client
echo and the new client. Both play the same game, account and bots.
echo.
echo   1 = Update my game. You already have Offline DAoC 0.36, 0.36b or 0.36c:
echo       a window opens, choose your game folder. Only the update is downloaded.
echo       Your account, characters, bots and settings stay as they are. If the
echo       game doesn't have the new client yet, it asks whether to add it.
echo   2 = New install. You don't have the game yet: it downloads the complete
echo       game (about 5 GB) and the new client (about 30 GB) into a new folder
echo       next to this file and updates both.
echo.
choice /c 12 /n /m "Press 1 or 2: "
if errorlevel 2 goto newinstall
echo.
echo Close the Offline DAoC launcher and the game first.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-OfflineDAoC.ps1" -ReleaseVersion 0.37c -Update pick
if errorlevel 1 goto failed
goto done

:newinstall
echo.
echo Which game do you want with the new client?
echo   1 = 0.37, the original Classic + Shrouded Isles classes only
echo   2 = 0.37b, with the custom Sluaghbinder class
choice /c 12 /n /m "Press 1 or 2: "
if errorlevel 2 (
  set "FOLDER=playable-v0.37c"
  set "CLASSIC="
) else (
  set "FOLDER=playable-v0.37c-classic"
  set "CLASSIC=-Classic"
)
echo.
echo This downloads, into a NEW folder called %FOLDER% next to this file, the
echo complete game (about 5 GB), the new client (about 30 GB) and the update.
echo Allow about 60 GB of free disk space while it installs. If it stops, run
echo this file again and press the same numbers: it continues where it stopped.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-OfflineDAoC.ps1" -ReleaseVersion 0.37c %CLASSIC% -Destination "%~dp0%FOLDER%"
if errorlevel 1 goto failed
echo.
echo Open the %FOLDER% folder and read READ ME - NEW CLIENT.txt.
echo   START OFFLINE DAOC - NEW CLIENT.cmd   plays with the new client
echo   START OFFLINE DAOC.cmd               plays with the original client

:done
echo.
pause
exit /b 0

:failed
echo.
echo It did not finish. Run this file again to continue; finished downloads are kept.
pause
exit /b 1
