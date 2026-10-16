# Installs this fork server build into an Offline DAoC game folder (docs/RELEASE-PLAN.md).
#
#   INSTALL.cmd                                  (finds the game folder this build sits in)
#   INSTALL.cmd -GameFolder "C:\Games\OfflineDAoC\playable-v0.36b"
#   INSTALL.cmd -DryRun                          (checks everything, changes nothing)
#
# Safe by design:
# - refuses while the server, launcher or game runs;
# - installs only into the release it was built for (BaseRelease in BUILD-INFO.txt), checked against
#   the game's own PACKAGE MANIFEST.sha256;
# - replaces only a GameServer.dll that is the original release file or a fork build this script
#   installed; anything else is refused unless -Force;
# - backs up every file it replaces under runtime\server\deployment-backups\fork-build-<time>\ and
#   verifies every copy by SHA-256. ROLLBACK.cmd restores the backup.
param(
    [string]$GameFolder = '',
    [switch]$DryRun,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fork-build-common.ps1')

$buildDir = $PSScriptRoot
$infoPath = Join-Path $buildDir 'BUILD-INFO.txt'
if (!(Test-Path -LiteralPath $infoPath)) { Stop-WithMessage 'BUILD-INFO.txt is missing from this build folder.' }
$info = Read-KeyValueFile $infoPath
foreach ($key in @('BuildName', 'BaseRelease', 'Commit', 'GameServer.dll', 'GameServer.pdb')) {
    if (!$info[$key]) { Stop-WithMessage "BUILD-INFO.txt has no $key." }
}
Write-Host "Fork server build $($info['BuildName']) (commit $($info['Commit'])) for Offline DAoC $($info['BaseRelease'])"

# 1. This build's own files must be intact.
foreach ($name in @('GameServer.dll', 'GameServer.pdb')) {
    $path = Join-Path $buildDir $name
    if (!(Test-Path -LiteralPath $path)) { Stop-WithMessage "$name is missing from this build folder." }
    if ((Get-Sha256 $path) -ne $info[$name].ToLowerInvariant()) {
        Stop-WithMessage "$name doesn't match BUILD-INFO.txt (damaged download?). Download the build again."
    }
}

# 2. The game, closed.
$game = Find-GameFolder $GameFolder $buildDir
Write-Host "Game folder: $game"
Assert-GameClosed

# 3. The right release.
$manifest = Read-PackageManifest $game
$base = $info['BaseRelease']
if ($null -eq $manifest) {
    if (!$Force) { Stop-WithMessage "No PACKAGE MANIFEST.sha256 in the game folder, so it can't be checked as Offline DAoC $base. (-Force skips this check.)" }
    $manifest = @{}
} elseif (!($manifest.Keys | Where-Object { $_ -like "editions/$base-no-custom-class/*" } | Select-Object -First 1)) {
    if (!$Force) { Stop-WithMessage "This game folder isn't Offline DAoC $base (or $($base)b). This build only fits $base; installing it on another release would undo that release's server changes." }
}

# 4. What is there now.
$knownFork = @{}
foreach ($record in Get-InstallRecords $game) {
    foreach ($entry in $record.Folders) { if ($entry.NewDll) { $knownFork[$entry.NewDll] = $record.BuildName } }
}
$newDll = $info['GameServer.dll'].ToLowerInvariant()
$newPdb = $info['GameServer.pdb'].ToLowerInvariant()
$plan = @()
foreach ($folder in $Script:ServerFolders) {
    $dll = Join-Path $game (Join-Path $folder 'GameServer.dll')
    if (!(Test-Path -LiteralPath $dll)) { continue }
    $hash = Get-Sha256 $dll
    $state = if ($hash -eq $newDll) { 'this build' }
        elseif ($manifest["$folder/GameServer.dll"] -and $hash -eq $manifest["$folder/GameServer.dll"]) { "original $base" }
        elseif ($knownFork.ContainsKey($hash)) { "fork build $($knownFork[$hash])" }
        else { 'unknown' }
    $plan += [pscustomobject]@{ Folder = $folder; Hash = $hash; State = $state }
    Write-Host ("  {0,-26} {1}" -f $folder, $state)
}
if ($plan.Count -eq 0) { Stop-WithMessage 'No GameServer.dll found under runtime\server.' }
if (@($plan | Where-Object { $_.State -eq 'unknown' }).Count -gt 0 -and !$Force) {
    Stop-WithMessage ("A GameServer.dll above is neither the original $base file nor a fork build this script installed. " +
        'Someone changed it by hand? Restore the original first, or run with -Force to replace it anyway (it is still backed up).')
}
if (@($plan | Where-Object { $_.State -ne 'this build' }).Count -eq 0) {
    Write-Host ''
    Write-Host "Already installed: $($info['BuildName']). Nothing to do." -ForegroundColor Green
    exit 0
}
if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: every check passed. Nothing was changed.' -ForegroundColor Green
    exit 0
}

# 5. Back up, copy, verify.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $game "runtime\server\deployment-backups\fork-build-$stamp"
New-Item -ItemType Directory -Path $backup | Out-Null
$entries = @()
foreach ($item in $plan) {
    $source = Join-Path $game $item.Folder
    $saved = Join-Path $backup (Get-BackupName $item.Folder)
    New-Item -ItemType Directory -Path $saved | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'GameServer.dll') -Destination $saved
    $oldPdb = $null
    if (Test-Path -LiteralPath (Join-Path $source 'GameServer.pdb')) {
        Copy-Item -LiteralPath (Join-Path $source 'GameServer.pdb') -Destination $saved
        $oldPdb = Get-Sha256 (Join-Path $saved 'GameServer.pdb')
    }
    if ((Get-Sha256 (Join-Path $saved 'GameServer.dll')) -ne $item.Hash) { Stop-WithMessage "Backup of $($item.Folder) failed verification." }
    $entries += [pscustomobject]@{ Folder = $item.Folder; OldDll = $item.Hash; OldPdb = $oldPdb; NewDll = $newDll; NewPdb = $newPdb }
}

# Helper scripts (settings switches) go to tools\claude-version, where they find the database.
$helpers = @()
$helperSource = Join-Path $buildDir 'tools\claude-version'
if (Test-Path -LiteralPath $helperSource) {
    $helperTarget = Join-Path $game 'tools\claude-version'
    foreach ($file in Get-ChildItem -LiteralPath $helperSource -File) {
        $target = Join-Path $helperTarget $file.Name
        $had = Test-Path -LiteralPath $target
        if ($had) {
            $savedHelpers = Join-Path $backup 'helpers'
            New-Item -ItemType Directory -Path $savedHelpers -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $savedHelpers
        }
        $helpers += [pscustomobject]@{ Name = $file.Name; Existed = $had; New = (Get-Sha256 $file.FullName) }
    }
}

$record = [pscustomobject]@{
    BuildName = $info['BuildName']; BaseRelease = $base; Commit = $info['Commit']
    Installed = (Get-Date).ToString('o'); GameFolder = $game; Folders = $entries; Helpers = $helpers
}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'install-record.json') -Encoding UTF8

try {
    foreach ($entry in $entries) {
        $target = Join-Path $game $entry.Folder
        Copy-Item -LiteralPath (Join-Path $buildDir 'GameServer.dll') -Destination $target -Force
        Copy-Item -LiteralPath (Join-Path $buildDir 'GameServer.pdb') -Destination $target -Force
        if ((Get-Sha256 (Join-Path $target 'GameServer.dll')) -ne $newDll -or (Get-Sha256 (Join-Path $target 'GameServer.pdb')) -ne $newPdb) {
            throw "Copy into $($entry.Folder) failed verification."
        }
    }
    if ($helpers.Count -gt 0) {
        New-Item -ItemType Directory -Path (Join-Path $game 'tools\claude-version') -Force | Out-Null
        foreach ($helper in $helpers) {
            Copy-Item -LiteralPath (Join-Path $helperSource $helper.Name) -Destination (Join-Path $game 'tools\claude-version') -Force
        }
    }
    $docs = Join-Path $buildDir 'docs'
    if (Test-Path -LiteralPath $docs) {
        $docsTarget = Join-Path $game "docs\fork-build-$($info['BuildName'])"
        New-Item -ItemType Directory -Path $docsTarget -Force | Out-Null
        Copy-Item -Path (Join-Path $docs '*') -Destination $docsTarget -Recurse -Force
    }
} catch {
    Write-Host "Install failed: $($_.Exception.Message). Restoring the backup..." -ForegroundColor Red
    foreach ($entry in $entries) {
        $saved = Join-Path $backup (Get-BackupName $entry.Folder)
        $target = Join-Path $game $entry.Folder
        Copy-Item -LiteralPath (Join-Path $saved 'GameServer.dll') -Destination $target -Force
        if ($entry.OldPdb) { Copy-Item -LiteralPath (Join-Path $saved 'GameServer.pdb') -Destination $target -Force }
        elseif (Test-Path -LiteralPath (Join-Path $target 'GameServer.pdb')) { Remove-Item -LiteralPath (Join-Path $target 'GameServer.pdb') }
    }
    Set-Content -LiteralPath (Join-Path $backup 'rolled-back.txt') -Value "Install failed and was undone at $(Get-Date -Format o)."
    Write-Host 'The original files are back in place.'
    exit 1
}

Write-Host ''
Write-Host "Installed $($info['BuildName']) into $($entries.Count) folder(s)." -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host "Start the game as usual. The server log shows: FORK_BUILD name=$($info['BuildName']) commit=$($info['Commit'])"
Write-Host 'Every new feature is OFF until you switch it on (see the docs folder). To undo: ROLLBACK.cmd'
exit 0
