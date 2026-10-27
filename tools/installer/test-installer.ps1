# End-to-end checks of the Living Server Setup exe on a real Windows PC (GitHub's windows runners in CI):
# a real download of Offline DAoC from shadowofze's releases, then every path Setup takes with it.
#
#   powershell -File tools\installer\test-installer.ps1 -Exe dist\LivingServer-Setup-1.0-beta.exe -Package payload\LivingServer.zip -Work C:\lstest
#
# Scenarios (all by default, in this order, sharing one download cache):
#   fresh     new install of the b edition with Living Server; scan; run again (already installed); refuse while the
#             game runs; remove; reinstall; refuse a hand-changed server, then -Force
#   update036 shadowofze's 0.36b installed with his own downloader, the 0.36 Social Expansion build on top, then Setup:
#             released server back, official update to 0.37, Living Server
param(
    [Parameter(Mandatory)] [string]$Exe,
    [Parameter(Mandatory)] [string]$Package,
    [string]$Work = 'C:\lstest',
    [string[]]$Scenario = @('fresh', 'update036')
)
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
$Package = (Resolve-Path $Package).Path
$root = Join-Path $Work 'games'
$logs = Join-Path $Work 'logs'
New-Item -ItemType Directory -Force -Path $root, $logs | Out-Null
$failures = New-Object System.Collections.Generic.List[string]
$script:n = 0

function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "  PASS  $what" -ForegroundColor Green }
    else { Write-Host "  FAIL  $what" -ForegroundColor Red; $failures.Add($what) }
}

function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

# BUILD-INFO.txt of the package the exe embeds
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($Package)
$info = @{}
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -match '^[^/]+/BUILD-INFO\.txt$' } | Select-Object -First 1
    $reader = New-Object IO.StreamReader($entry.Open())
    foreach ($line in ($reader.ReadToEnd() -split "`r?`n")) { if ($line -match '^\s*([^=#]+?)\s*=\s*(.*?)\s*$') { $info[$Matches[1]] = $Matches[2] } }
    $reader.Dispose()
    $pkgRoot = $entry.FullName.Split('/')[0]
} finally { $zip.Dispose() }
Write-Host "Package $($info['BuildName']) for $($info['BaseRelease']) (root folder $pkgRoot)"

function Setup([string]$name, [string[]]$argList) {
    $script:n++
    $log = Join-Path $logs ('{0:00}-{1}.log' -f $script:n, $name)
    $all = @('--silent') + $argList + @('--log', $log)
    Write-Host ''
    Write-Host "== $name : Setup $($all -join ' ')" -ForegroundColor Cyan
    $start = Get-Date
    $p = Start-Process -FilePath $Exe -ArgumentList ($all | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -Wait -PassThru -NoNewWindow
    $text = if (Test-Path $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    $tail = ($text -split "`r?`n" | Where-Object { $_ -match 'STEP |RESULT |\[ *\d+%\]|FAILED|NOTHING WAS CHANGED' } | Select-Object -Last 40) -join "`n"
    Write-Host $tail
    Write-Host ("   exit {0} after {1:N0} s" -f $p.ExitCode, ((Get-Date) - $start).TotalSeconds)
    return [pscustomobject]@{ Code = $p.ExitCode; Log = $text }
}

function Assert-LivingServer([string]$game, [string]$what) {
    foreach ($f in 'runtime\server', 'runtime\server\lib', 'runtime\server\win-x64') {
        $dll = Join-Path $game "$f\GameServer.dll"
        if (Test-Path $dll) { Check ((Sha $dll) -eq $info['GameServer.dll'].ToLowerInvariant()) "$what : $f\GameServer.dll is the Living Server build" }
    }
    Check ((Sha (Join-Path $game 'runtime\OfflineDAoC.dll')) -eq $info['launcher/OfflineDAoC.dll'].ToLowerInvariant()) "$what : the launcher has the Living Server tab"
    Check (Test-Path (Join-Path $game "$pkgRoot\ROLLBACK.cmd")) "$what : the package folder (with ROLLBACK.cmd) is in the game"
    $rec = Get-ChildItem (Join-Path $game 'runtime\server\deployment-backups') -Directory -Filter 'fork-build-*' | Sort-Object Name | Select-Object -Last 1
    Check ($rec -and (Get-Content (Join-Path $rec.FullName 'install-record.json') -Raw | ConvertFrom-Json).BuildName -eq $info['BuildName']) "$what : the install record names $($info['BuildName'])"
}

function Released-ServerHash([string]$game) {
    foreach ($line in Get-Content -LiteralPath (Join-Path $game 'PACKAGE MANIFEST.sha256')) {
        if ($line -match '^([0-9a-fA-F]{64})\s+runtime/server/GameServer\.dll$') { return $Matches[1].ToLowerInvariant() }
    }
}

function Newest-Release([string]$game) {
    $v = Get-Content -LiteralPath (Join-Path $game 'PACKAGE MANIFEST.sha256') | ForEach-Object { if ($_ -match 'docs/RELEASE-(\d+\.\d+)\.md$') { [version]$Matches[1] } } | Sort-Object | Select-Object -Last 1
    return "$v"
}

$base = $info['BaseRelease']
$fresh = Join-Path $root "playable-v$($base)b"
Get-PSDrive -PSProvider FileSystem | Format-Table Name, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}, @{n='UsedGB';e={[math]::Round($_.Used/1GB,1)}} | Out-String | Write-Host

if ($Scenario -contains 'fresh') {
    $r = Setup 'fresh-install' @('--new', '--dest', $fresh)
    Check ($r.Code -eq 0) 'fresh: Setup finished'
    Check ((Newest-Release $fresh) -eq $base) "fresh: the game is Offline DAoC $base"
    Check (!(Test-Path (Join-Path $fresh 'EDITION.txt'))) 'fresh: the b edition (no EDITION.txt)'
    Assert-LivingServer $fresh 'fresh'
    $desk = [Environment]::GetFolderPath('DesktopDirectory')
    Check (Test-Path (Join-Path $desk 'Offline DAoC.lnk')) 'fresh: desktop shortcut'
    Check (Test-Path (Join-Path ([Environment]::GetFolderPath('Programs')) 'Offline DAoC\Offline DAoC.lnk')) 'fresh: Start menu shortcut'
    $setupDir = Join-Path $root 'Offline DAoC setup files'
    Check (Test-Path (Join-Path $setupDir 'Get-OfflineDAoC.ps1')) 'fresh: the official downloader sits in the setup files folder'
    Check ($r.Log -match 'STEP Done: Download Offline DAoC' -and $r.Log -match 'STEP Done: Update the game to') 'fresh: download and update steps reported done'
    Check ($r.Log -match '\[ *(5\d|6\d|7\d)%\] Downloading Offline DAoC|\[ *\d+%\] Unpacking the game') 'fresh: progress was measured while downloading or unpacking'

    $r = Setup 'scan' @('--scan', '--game', $fresh)
    Check ($r.Log -match [regex]::Escape("GAME $fresh | $($base)b | LivingServer=ThisBuild")) 'scan: the game is found as this build'

    $r = Setup 'again' @('--game', $fresh, '--no-shortcuts')
    Check ($r.Code -eq 0 -and $r.Log -match 'Already installed') 'again: a second run changes nothing'

    # a program named like the launcher is running: Setup must refuse before touching anything
    $fake = Join-Path $Work 'OfflineDAoC.exe'
    Copy-Item "$env:SystemRoot\System32\ping.exe" $fake -Force
    $running = Start-Process -FilePath $fake -ArgumentList '-n 120 127.0.0.1' -PassThru -WindowStyle Hidden
    Start-Sleep 2
    $r = Setup 'while-running' @('--game', $fresh, '--no-shortcuts')
    Check ($r.Code -eq 1 -and $r.Log -match 'still running') 'running: Setup refuses while Offline DAoC runs'
    Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep 1

    $r = Setup 'remove' @('--game', $fresh, '--remove')
    $released = Released-ServerHash $fresh
    Check ($r.Code -eq 0) 'remove: Setup finished'
    Check ((Sha (Join-Path $fresh 'runtime\server\GameServer.dll')) -eq $released) 'remove: the released server is back'
    $r = Setup 'scan-after-remove' @('--scan', '--game', $fresh)
    Check ($r.Log -match [regex]::Escape("GAME $fresh | $($base)b | LivingServer=None")) 'remove: the game scans as plain Offline DAoC'

    $r = Setup 'reinstall' @('--game', $fresh, '--no-shortcuts')
    Check ($r.Code -eq 0) 'reinstall: Setup finished'
    Assert-LivingServer $fresh 'reinstall'

    # a server file changed by hand: refused, then replaced with --force (backed up)
    $r = Setup 'remove-again' @('--game', $fresh, '--remove')
    $lib = Join-Path $fresh 'runtime\server\lib\GameServer.dll'
    [IO.File]::AppendAllText($lib, ' ')
    $changed = Sha $lib
    $r = Setup 'changed-by-hand' @('--game', $fresh, '--no-shortcuts')
    Check ($r.Code -eq 1 -and $r.Log -match '\[can --force\]') 'changed: Setup refuses a hand-changed server and offers to replace it'
    $r = Setup 'force' @('--game', $fresh, '--no-shortcuts', '--force')
    Check ($r.Code -eq 0) 'force: Setup replaces it'
    Assert-LivingServer $fresh 'force'
    $backup = Get-ChildItem (Join-Path $fresh 'runtime\server\deployment-backups') -Directory -Filter 'fork-build-*' | Sort-Object Name | Select-Object -Last 1
    Check ((Sha (Join-Path $backup.FullName 'runtime_server_lib\GameServer.dll')) -eq $changed) 'force: the hand-changed file was backed up'
}

if ($Scenario -contains 'update036') {
    $old = Join-Path $root 'playable-v0.36b'
    $setupDir = Join-Path $root 'Offline DAoC setup files'
    New-Item -ItemType Directory -Force -Path $setupDir | Out-Null
    $repoDownloader = Join-Path $PSScriptRoot '..\..\Get-OfflineDAoC.ps1'
    Copy-Item $repoDownloader (Join-Path $setupDir 'Get-OfflineDAoC.ps1') -Force
    Write-Host ''
    Write-Host '== update036: shadowofze''s own downloader installs 0.36b (same download cache)' -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $setupDir 'Get-OfflineDAoC.ps1') -ReleaseVersion 0.36b -Destination $old | Select-Object -Last 3
    Check ((Newest-Release $old) -eq '0.36') 'update036: a 0.36b game to start from'

    # the 0.36 Social Expansion build on it, as players had it
    $seZip = Join-Path $Work 'se.zip'
    Invoke-WebRequest -UseBasicParsing 'https://github.com/chris4aker/OfflineDAoC-LivingServer/releases/download/v0.36-se.1/OfflineDAoC-SocialExpansion-0.36-se.1.zip' -OutFile $seZip
    Expand-Archive $seZip -DestinationPath $old -Force
    $seDir = Get-ChildItem $old -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'install-server-build.ps1') } | Select-Object -First 1
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $seDir.FullName 'install-server-build.ps1') -GameFolder $old | Select-Object -Last 3
    $r = Setup 'scan-036' @('--scan', '--game', $old)
    Check ($r.Log -match 'LivingServer=OtherBuild \(0\.36-se\.1\)') 'update036: the Social Expansion build is recognised'

    $r = Setup 'update-036-to-base' @('--game', $old, '--no-shortcuts')
    Check ($r.Code -eq 0) 'update036: Setup finished'
    Check ($r.Log -match 'STEP Done: Put the released server back') 'update036: the released server went back first'
    Check ((Newest-Release $old) -eq $base) "update036: the game is Offline DAoC $base now"
    Assert-LivingServer $old 'update036'
}

Write-Host ''
Get-PSDrive -PSProvider FileSystem | Format-Table Name, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}} | Out-String | Write-Host
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) check(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
