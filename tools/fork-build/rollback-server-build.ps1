# Undoes the most recent fork server build install (docs/RELEASE-PLAN.md).
#
#   ROLLBACK.cmd
#   ROLLBACK.cmd -GameFolder "C:\Games\OfflineDAoC\playable-v0.35"
#   ROLLBACK.cmd -DryRun
#
# Restores the GameServer.dll/.pdb files and helper scripts the last install replaced, from its
# backup, and checks every restored file by SHA-256. It refuses if the installed files changed since
# (unless -Force). Run it again to undo the install before that one.
param(
    [string]$GameFolder = '',
    [switch]$DryRun,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fork-build-common.ps1')

$game = Find-GameFolder $GameFolder $PSScriptRoot
Write-Host "Game folder: $game"
Assert-GameClosed

$record = Get-InstallRecords $game | Where-Object { !$_.RolledBack } | Select-Object -Last 1
if ($null -eq $record) { Stop-WithMessage 'No fork build install to undo.' }
Write-Host "Undoing $($record.BuildName) installed $($record.Installed)"

foreach ($entry in $record.Folders) {
    $dll = Join-Path $game (Join-Path $entry.Folder 'GameServer.dll')
    $current = if (Test-Path -LiteralPath $dll) { Get-Sha256 $dll } else { '' }
    if ($current -ne $entry.NewDll -and !$Force) {
        Stop-WithMessage "$($entry.Folder)\GameServer.dll changed since that install (another build installed over it?). -Force restores the backup anyway."
    }
    $saved = Join-Path $record.BackupFolder (Get-BackupName $entry.Folder)
    if ((Get-Sha256 (Join-Path $saved 'GameServer.dll')) -ne $entry.OldDll) { Stop-WithMessage "The backup of $($entry.Folder) is damaged." }
}
if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: every check passed. Nothing was changed.' -ForegroundColor Green
    exit 0
}

foreach ($entry in $record.Folders) {
    $saved = Join-Path $record.BackupFolder (Get-BackupName $entry.Folder)
    $target = Join-Path $game $entry.Folder
    Copy-Item -LiteralPath (Join-Path $saved 'GameServer.dll') -Destination $target -Force
    if ($entry.OldPdb) { Copy-Item -LiteralPath (Join-Path $saved 'GameServer.pdb') -Destination $target -Force }
    elseif (Test-Path -LiteralPath (Join-Path $target 'GameServer.pdb')) { Remove-Item -LiteralPath (Join-Path $target 'GameServer.pdb') }
    if ((Get-Sha256 (Join-Path $target 'GameServer.dll')) -ne $entry.OldDll) { Stop-WithMessage "Restoring $($entry.Folder) failed verification." }
}
foreach ($helper in @($record.Helpers)) {
    if ($null -eq $helper) { continue }
    $target = Join-Path $game (Join-Path 'tools\claude-version' $helper.Name)
    if ($helper.Existed) {
        Copy-Item -LiteralPath (Join-Path $record.BackupFolder (Join-Path 'helpers' $helper.Name)) -Destination $target -Force
    } elseif ((Test-Path -LiteralPath $target) -and (Get-Sha256 $target) -eq $helper.New) {
        Remove-Item -LiteralPath $target
    }
}
Set-Content -LiteralPath (Join-Path $record.BackupFolder 'rolled-back.txt') -Value "Rolled back at $(Get-Date -Format o)."
Write-Host ''
Write-Host "Rolled back $($record.BuildName). The files it replaced are back." -ForegroundColor Green
Write-Host 'Settings it may have switched on stay in the database; turn features off with the helper scripts first if you want them gone.'
exit 0
