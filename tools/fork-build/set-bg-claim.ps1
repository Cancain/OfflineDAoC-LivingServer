# Fork: switches the battleground keep claim settings (ForkKeepClaims) in a stopped server's world database.
#
#   set-bg-claim.ps1 -Database D:\OfflineDAOC\dev-v0.37\runtime\data\opendaoc.sqlite3.db -BgClaim on -DryRun
#   set-bg-claim.ps1 -Database ... -BgClaim on -CountGroupBots on -BgClaimLimit 1
#   set-bg-claim.ps1 -Database ... -BgClaim off -CountGroupBots off -BotGuildsClaimBg off
#
#   -BgClaim            fork_bg_claim: guilds may claim battleground keeps (never portal or relic keeps), which keep their level
#   -CountGroupBots     fork_claim_counts_group_bots: the group's companions and bots in the keep area count towards claim_num
#   -BotGuildsClaimBg   fork_bot_guilds_claim_bg: bot guilds may claim battleground keeps too (needs -BgClaim on)
#   -BgClaimLimit       fork_bg_claim_limit: battleground keeps a guild may claim (frontier keeps use guilds_claim_limit)
#
# Safe by design: refuses while the server, launcher or game runs; only accepts the dev copy's database for now; shows
# the changes with the database opened read-only, then backs it up (with its -wal and -shm) before writing anything.
# -DryRun stops after showing them. Needs the .NET 10 SDK (dotnet run set-bg-claim.cs). Settings take effect the next
# time the server starts.
param(
    [Parameter(Mandatory = $true)][string]$Database,
    [ValidateSet('on', 'off')][string]$BgClaim,
    [ValidateSet('on', 'off')][string]$CountGroupBots,
    [ValidateSet('on', 'off')][string]$BotGuildsClaimBg,
    [ValidateRange(0, 100)][Nullable[int]]$BgClaimLimit,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fork-build-common.ps1')

# Only the dev copy until this script has been used there (the fork's rules in CLAUDE.md).
$AllowedFolder = 'D:\OfflineDAOC\dev-v0.37\runtime\data\'

$full = [IO.Path]::GetFullPath($Database)
if (!$full.StartsWith($AllowedFolder, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-WithMessage "Only the dev copy's database ($AllowedFolder) is allowed for now, not '$full'."
}
if (!(Test-Path -LiteralPath $full)) { Stop-WithMessage "No database at '$full'." }

$settings = @()
if ($BgClaim) { $settings += "fork_bg_claim=$BgClaim" }
if ($CountGroupBots) { $settings += "fork_claim_counts_group_bots=$CountGroupBots" }
if ($BotGuildsClaimBg) { $settings += "fork_bot_guilds_claim_bg=$BotGuildsClaimBg" }
if ($null -ne $BgClaimLimit) { $settings += "fork_bg_claim_limit=$BgClaimLimit" }

Assert-GameClosed
if (Get-NetTCPConnection -LocalPort 10300 -ErrorAction SilentlyContinue) {
    Stop-WithMessage 'Something is listening on port 10300 (a server is running).'
}

# The first dotnet that has an SDK: a user install (dotnet-install.ps1) first, then the one on PATH.
$dotnetPath = $null
foreach ($candidate in @("$env:LOCALAPPDATA\Microsoft\dotnet\dotnet.exe", (Get-Command dotnet -ErrorAction SilentlyContinue).Source)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $candidate) 'sdk'))) {
        $dotnetPath = $candidate
        break
    }
}
if (!$dotnetPath) { Stop-WithMessage 'No .NET 10 SDK (dotnet with an sdk folder) was found.' }
$env:DOTNET_ROOT = Split-Path -Parent $dotnetPath
$tool = Join-Path $PSScriptRoot 'set-bg-claim.cs'

# 1. What would change, read-only (exit 10: changes to make).
& $dotnetPath run $tool -- $full dry @settings
$code = $LASTEXITCODE
if ($DryRun -or $code -ne 10) {
    if ($code -eq 10) { exit 0 }
    exit $code
}

# 2. Back up, then write.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path (Split-Path -Parent $full) "fork-backups\bg-claim-$stamp"
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($file in @($full, "$full-wal", "$full-shm")) {
    if (!(Test-Path -LiteralPath $file)) { continue }
    Copy-Item -LiteralPath $file -Destination $backup
    if ((Get-Sha256 $file) -ne (Get-Sha256 (Join-Path $backup (Split-Path -Leaf $file)))) {
        Stop-WithMessage "Backup of $(Split-Path -Leaf $file) failed verification."
    }
}
Write-Host "Backup: $backup"
& $dotnetPath run $tool -- $full apply @settings
exit $LASTEXITCODE
