# Shared by install-server-build.ps1 and rollback-server-build.ps1 (docs/RELEASE-PLAN.md).
# Windows PowerShell 5.1 compatible.

$Script:ServerFolders = @('runtime/server', 'runtime/server/lib', 'runtime/server/win-x64')
$Script:ProcessNames = @('CoreServer', 'DOLServer', 'OfflineDAoC', 'game')

function Stop-WithMessage([string]$Message) {
    Write-Host ''
    Write-Host "NOTHING WAS CHANGED: $Message" -ForegroundColor Red
    exit 1
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-KeyValueFile([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([^=#]+?)\s*=\s*(.*?)\s*$') { $values[$Matches[1]] = $Matches[2] }
    }
    return $values
}

function Test-GameFolder([string]$Path) {
    return $Path -and (Test-Path -LiteralPath (Join-Path $Path 'runtime\server\GameServer.dll'))
}

# The game folder: the one given, else the folder this build sits in (or its parents), or a
# playable*/OfflineDAoC* folder inside one of those.
function Find-GameFolder([string]$Given, [string]$BuildDir) {
    if ($Given) {
        $full = [IO.Path]::GetFullPath($Given)
        if (Test-GameFolder $full) { return $full }
        Stop-WithMessage "No Offline DAoC game in '$full' (runtime\server\GameServer.dll is missing)."
    }
    $starts = @()
    $parent = Split-Path -Parent $BuildDir
    if ($parent) { $starts += $parent; $grand = Split-Path -Parent $parent; if ($grand) { $starts += $grand } }
    $starts += $BuildDir
    $found = @()
    foreach ($start in $starts) {
        if (Test-GameFolder $start) { $found += [IO.Path]::GetFullPath($start); continue }
        foreach ($child in @(Get-ChildItem -LiteralPath $start -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'playable*' -or $_.Name -like 'OfflineDAoC*' })) {
            if (Test-GameFolder $child.FullName) { $found += $child.FullName }
        }
    }
    $found = @($found | Select-Object -Unique)
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) {
        Stop-WithMessage ("More than one game folder found. Run again with -GameFolder and one of:`n  " + ($found -join "`n  "))
    }
    Stop-WithMessage ("Can't find the game. Put this build's folder inside your Offline DAoC folder (the one with " +
        "START OFFLINE DAOC.cmd), or run INSTALL.cmd -GameFolder ""C:\path\to\playable-v0.35"".")
}

function Assert-GameClosed {
    $running = @(Get-Process -Name $Script:ProcessNames -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Stop-WithMessage ("Close the server, launcher and game first (running: " +
            (($running | ForEach-Object { $_.ProcessName } | Select-Object -Unique) -join ', ') + ').')
    }
}

# 'hash  relative/path' lines of the release's PACKAGE MANIFEST.sha256, keyed by path.
function Read-PackageManifest([string]$Game) {
    $path = Join-Path $Game 'PACKAGE MANIFEST.sha256'
    if (!(Test-Path -LiteralPath $path)) { return $null }
    $manifest = @{}
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^([0-9a-fA-F]{64})\s+(.+)$') { $manifest[$Matches[2].Trim()] = $Matches[1].ToLowerInvariant() }
    }
    return $manifest
}

function Get-InstallRecords([string]$Game) {
    $root = Join-Path $Game 'runtime\server\deployment-backups'
    if (!(Test-Path -LiteralPath $root)) { return @() }
    return @(Get-ChildItem -LiteralPath $root -Directory -Filter 'fork-build-*' |
        Sort-Object Name |
        ForEach-Object {
            $file = Join-Path $_.FullName 'install-record.json'
            if (Test-Path -LiteralPath $file) {
                $record = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                $record | Add-Member -NotePropertyName BackupFolder -NotePropertyValue $_.FullName -Force
                $record | Add-Member -NotePropertyName RolledBack -NotePropertyValue (Test-Path -LiteralPath (Join-Path $_.FullName 'rolled-back.txt')) -Force
                $record
            }
        })
}

function Get-BackupName([string]$Folder) { return ($Folder -replace '[\\/]', '_') }
