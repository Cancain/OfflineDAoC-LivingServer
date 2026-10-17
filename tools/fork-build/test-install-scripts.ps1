# Tests install-server-build.ps1 and rollback-server-build.ps1 against fake game folders.
# Run by CI on Windows PowerShell 5.1:  powershell -File tools\fork-build\test-install-scripts.ps1 -BuildDir <package folder>
param([Parameter(Mandatory = $true)][string]$BuildDir)
$ErrorActionPreference = 'Stop'
$failures = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "PASS  $what"; return }
    Write-Host "FAIL  $what" -ForegroundColor Red
    $script:failures++
    # CI annotations are readable without the job log.
    if ($env:GITHUB_ACTIONS) { Write-Host ("::error title=Installer test::" + (($what -replace "`r", '') -replace "`n", ' | ').Substring(0, [Math]::Min(900, $what.Length))) }
}
function Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Run([string]$scriptName, [string[]]$arguments) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BuildDir $scriptName) @arguments 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}
$launcherFiles = @('OfflineDAoC.dll', 'OfflineDAoC.exe', 'OfflineDAoC.pdb', 'OfflineDAoC.deps.json', 'OfflineDAoC.runtimeconfig.json')
function New-FakeLauncher([string]$dir, [string]$prefix) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $lines = @()
    foreach ($name in $launcherFiles) {
        [IO.File]::WriteAllText((Join-Path $dir $name), "original launcher $name")
        $lines += "$(Sha (Join-Path $dir $name))  $prefix/$name"
    }
    return $lines
}
function New-FakeGame([string]$root, [string]$edition, [switch]$NewClient) {
    $folders = @('runtime/server', 'runtime/server/lib', 'runtime/server/win-x64')
    $lines = @()
    foreach ($folder in $folders) {
        $dir = Join-Path $root $folder
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'GameServer.dll'), "original release server")
        [IO.File]::WriteAllText((Join-Path $dir 'GameServer.pdb'), "original release symbols")
        $lines += "$(Sha (Join-Path $dir 'GameServer.dll'))  $folder/GameServer.dll"
        $lines += "$(Sha (Join-Path $dir 'GameServer.pdb'))  $folder/GameServer.pdb"
    }
    $lines += New-FakeLauncher (Join-Path $root 'runtime') 'runtime'
    if ($NewClient) {
        $client = New-FakeLauncher (Join-Path $root 'new-client\runtime') 'new-client/runtime'
        Set-Content -LiteralPath (Join-Path $root 'new-client\PACKAGE MANIFEST.sha256') -Value $client -Encoding UTF8
    }
    $editionFile = Join-Path $root "editions\$edition-no-custom-class\runtime\x.txt"
    New-Item -ItemType Directory -Path (Split-Path -Parent $editionFile) -Force | Out-Null
    [IO.File]::WriteAllText($editionFile, 'edition')
    $lines += "$(Sha $editionFile)  editions/$edition-no-custom-class/runtime/x.txt"
    Set-Content -LiteralPath (Join-Path $root 'PACKAGE MANIFEST.sha256') -Value $lines -Encoding UTF8
}

$info = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $BuildDir 'BUILD-INFO.txt')) { if ($line -match '^(.+?)=(.*)$') { $info[$Matches[1]] = $Matches[2] } }
$base = $info['BaseRelease']
$work = Join-Path ([IO.Path]::GetTempPath()) ('forkbuild-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

# Happy path: install, reinstall is a no-op, rollback restores the originals.
$game = Join-Path $work 'good'
New-FakeGame $game $base -NewClient
$originalLauncher = Sha (Join-Path $game 'runtime\OfflineDAoC.dll')
$original = Sha (Join-Path $game 'runtime\server\lib\GameServer.dll')
$dry = Run 'install-server-build.ps1' @('-GameFolder', $game, '-DryRun')
Check ($dry.Code -eq 0 -and (Sha (Join-Path $game 'runtime\server\lib\GameServer.dll')) -eq $original) 'dry run passes and changes nothing'
$install = Run 'install-server-build.ps1' @('-GameFolder', $game)
Check ($install.Code -eq 0) "install succeeds`n$($install.Output)"
foreach ($folder in @('runtime\server', 'runtime\server\lib', 'runtime\server\win-x64')) {
    Check ((Sha (Join-Path $game "$folder\GameServer.dll")) -eq $info['GameServer.dll']) "new dll in $folder"
    Check ((Sha (Join-Path $game "$folder\GameServer.pdb")) -eq $info['GameServer.pdb']) "new pdb in $folder"
}
foreach ($folder in @('runtime', 'new-client\runtime')) {
    foreach ($name in $launcherFiles) {
        Check ((Sha (Join-Path $game "$folder\$name")) -eq $info["launcher/$name"]) "new launcher $name in $folder"
    }
}
Check (Test-Path (Join-Path $game 'tools\claude-version\set_bot_guilds.py')) 'helper scripts installed'
Check (Test-Path (Join-Path $game 'tools\claude-version\set_bot_social.py')) 'social switch installed'
Check (@(Get-ChildItem (Join-Path $game 'runtime\server\deployment-backups') -Directory).Count -eq 1) 'one backup folder'
$again = Run 'install-server-build.ps1' @('-GameFolder', $game)
Check ($again.Code -eq 0 -and $again.Output -match 'Already installed') 'reinstall is a no-op'
Start-Sleep -Seconds 2   # backup folders are named to the second
[IO.File]::WriteAllText((Join-Path $game 'runtime\OfflineDAoC.exe'), 'half-copied launcher')
$halfway = Run 'install-server-build.ps1' @('-GameFolder', $game)
Check ($halfway.Code -eq 0 -and $halfway.Output -notmatch 'Already installed' -and
       (Sha (Join-Path $game 'runtime\OfflineDAoC.exe')) -eq $info['launcher/OfflineDAoC.exe']) "a half-copied launcher is installed again`n$($halfway.Output)"
$rollbackHalf = Run 'rollback-server-build.ps1' @('-GameFolder', $game)
Check ($rollbackHalf.Code -eq 0) "rollback of the repair install`n$($rollbackHalf.Output)"
$rollback = Run 'rollback-server-build.ps1' @('-GameFolder', $game)
Check ($rollback.Code -eq 0) "rollback succeeds`n$($rollback.Output)"
Check ((Sha (Join-Path $game 'runtime\server\lib\GameServer.dll')) -eq $original) 'rollback restores the original dll'
Check ((Sha (Join-Path $game 'runtime\OfflineDAoC.dll')) -eq $originalLauncher) 'rollback restores the original launcher'
Check ([IO.File]::ReadAllText((Join-Path $game 'new-client\runtime\OfflineDAoC.dll')) -eq 'original launcher OfflineDAoC.dll') 'rollback restores the new client launcher'
Check (!(Test-Path (Join-Path $game 'tools\claude-version\set_bot_guilds.py'))) 'rollback removes helpers it added'
Check (!(Test-Path (Join-Path $game 'tools\claude-version\set_bot_social.py'))) 'rollback removes the social switch'
$nothing = Run 'rollback-server-build.ps1' @('-GameFolder', $game)
Check ($nothing.Code -ne 0) 'a second rollback has nothing to undo'
$reinstall = Run 'install-server-build.ps1' @('-GameFolder', $game)
Check ($reinstall.Code -eq 0) 'install works again after a rollback'

# Wrong release: refused, nothing changed.
$other = Join-Path $work 'other'
New-FakeGame $other '9.99'
$wrong = Run 'install-server-build.ps1' @('-GameFolder', $other)
Check ($wrong.Code -ne 0 -and (Sha (Join-Path $other 'runtime\server\GameServer.dll')) -ne $info['GameServer.dll']) 'another release is refused'

# A hand-changed dll: refused.
$changed = Join-Path $work 'changed'
New-FakeGame $changed $base
[IO.File]::WriteAllText((Join-Path $changed 'runtime\server\GameServer.dll'), 'someone else''s build')
$unknown = Run 'install-server-build.ps1' @('-GameFolder', $changed)
Check ($unknown.Code -ne 0 -and (Sha (Join-Path $changed 'runtime\server\lib\GameServer.dll')) -ne $info['GameServer.dll']) 'an unknown dll is refused'

# A hand-changed launcher: refused, and the server is not touched either.
$changedLauncher = Join-Path $work 'changed-launcher'
New-FakeGame $changedLauncher $base
[IO.File]::WriteAllText((Join-Path $changedLauncher 'runtime\OfflineDAoC.dll'), 'someone else''s launcher')
$unknownLauncher = Run 'install-server-build.ps1' @('-GameFolder', $changedLauncher)
Check ($unknownLauncher.Code -ne 0 -and (Sha (Join-Path $changedLauncher 'runtime\server\GameServer.dll')) -ne $info['GameServer.dll']) 'an unknown launcher is refused'

# A game without the new client: only runtime's launcher is replaced.
$plain = Join-Path $work 'plain'
New-FakeGame $plain $base
$plainInstall = Run 'install-server-build.ps1' @('-GameFolder', $plain)
Check ($plainInstall.Code -eq 0 -and (Sha (Join-Path $plain 'runtime\OfflineDAoC.dll')) -eq $info['launcher/OfflineDAoC.dll'] -and
       !(Test-Path (Join-Path $plain 'new-client'))) "install without the new client`n$($plainInstall.Output)"

# No game: refused.
$none = Run 'install-server-build.ps1' @('-GameFolder', (Join-Path $work 'missing'))
Check ($none.Code -ne 0) 'a missing game folder is refused'

Remove-Item -LiteralPath $work -Recurse -Force
if ($failures -gt 0) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All installer checks passed.' -ForegroundColor Green
exit 0
