@echo off
setlocal
cd /d "%~dp0"
rem Offline DAoC 0.37c - the new client. It plays the same game as START OFFLINE DAOC.cmd: same server,
rem same account, same characters, same bots. Run one launcher at a time.
if not exist "%~dp0runtime\OfflineDAoC.exe" (
  echo The new client belongs inside an Offline DAoC game folder, next to START OFFLINE DAOC.cmd.
  echo Use GET-OFFLINE-DAOC-v0.37c.cmd from the 0.37c release page to install it.
  pause
  exit /b 1
)
if not exist "%~dp0new-client\runtime\OfflineDAoC.exe" goto incomplete
if not exist "%~dp0new-client\godot\project.godot" goto incomplete
if exist "%~dp0new-client\INSTALLING.txt" goto incomplete
set "DOTNET_ROOT=%~dp0tools\dotnet"
set "DOTNET_ROOT_X64=%~dp0tools\dotnet"
set "DOTNET_MULTILEVEL_LOOKUP=0"
start "" "%~dp0new-client\runtime\OfflineDAoC.exe"
exit /b 0

:incomplete
echo The new client is not fully installed yet.
echo Run GET-OFFLINE-DAOC-v0.37c.cmd (or the file you used) again
echo (the one you used): it finishes the download where it stopped.
pause
exit /b 1
