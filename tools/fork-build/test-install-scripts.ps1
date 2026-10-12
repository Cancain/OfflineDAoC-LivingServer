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
function New-FakeGame([string]$root, [string]$edition) {
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
New-FakeGame $game $base
$original = Sha (Join-Path $game 'runtime\server\lib\GameServer.dll')
$dry = Run 'install-server-build.ps1' @('-GameFolder', $game, '-DryRun')
Check ($dry.Code -eq 0 -and (Sha (Join-Path $game 'runtime\server\lib\GameServer.dll')) -eq $original) 'dry run passes and changes nothing'
$install = Run 'install-server-build.ps1' @('-GameFolder', $game)
Check ($install.Code -eq 0) "install succeeds`n$($install.Output)"
foreach ($folder in @('runtime\server', 'runtime\server\lib', 'runtime\server\win-x64')) {
    Check ((Sha (Join-Path $game "$folder\GameServer.dll")) -eq $info['GameServer.dll']) "new dll in $folder"
    Check ((Sha (Join-Path $game "$folder\GameServer.pdb")) -eq $info['GameServer.pdb']) "new pdb in $folder"
}
Check (Test-Path (Join-Path $game 'tools\claude-version\set_bot_guilds.py')) 'helper scripts installed'
Check (Test-Path (Join-Path $game 'tools\claude-version\set_bot_social.py')) 'social switch installed'
Check (@(Get-ChildItem (Join-Path $game 'runtime\server\deployment-backups') -Directory).Count -eq 1) 'one backup folder'
$again = Run 'install-server-build.ps1' @('-GameFolder', $game)
Check ($again.Code -eq 0 -and $again.Output -match 'Already installed') 'reinstall is a no-op'
$rollback = Run 'rollback-server-build.ps1' @('-GameFolder', $game)
Check ($rollback.Code -eq 0) "rollback succeeds`n$($rollback.Output)"
Check ((Sha (Join-Path $game 'runtime\server\lib\GameServer.dll')) -eq $original) 'rollback restores the original dll'
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

# No game: refused.
$none = Run 'install-server-build.ps1' @('-GameFolder', (Join-Path $work 'missing'))
Check ($none.Code -ne 0) 'a missing game folder is refused'

Remove-Item -LiteralPath $work -Recurse -Force
if ($failures -gt 0) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All installer checks passed.' -ForegroundColor Green
exit 0
