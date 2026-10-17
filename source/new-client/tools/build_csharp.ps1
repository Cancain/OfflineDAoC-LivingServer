# Rebuilds the game's C# part only when a .cs file is newer than what was built - run it after editing a .cs file
# (the game's C# (godot\MMOEngine.csproj: your companions' bot code). Portable (owner 2026-10-11): the .NET SDK in tools\dotnet and the package
# cache in tools\nuget, offline (godot\nuget.config: the Godot .NET build's own packages).
$root = Split-Path -Parent $PSScriptRoot
$dotnetDir = Join-Path $root 'tools\dotnet'
if (Test-Path (Join-Path $dotnetDir 'dotnet.exe')) {
	$env:DOTNET_ROOT = $dotnetDir
	$env:DOTNET_ROOT_X64 = $dotnetDir
	$env:DOTNET_MULTILEVEL_LOOKUP = '0'
	$env:DOTNET_CLI_HOME = Join-Path $root 'tools\dotnet_home'
	$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
	$env:DOTNET_NOLOGO = '1'
	$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
	$env:NUGET_PACKAGES = Join-Path $root 'tools\nuget'
	$env:PATH = "$dotnetDir;$env:PATH"
}
$dotnet = if (Test-Path (Join-Path $dotnetDir 'dotnet.exe')) { Join-Path $dotnetDir 'dotnet.exe' } else { 'dotnet' }

function Newest($dir) {
	Get-ChildItem $dir -Recurse -Filter *.cs | Where-Object { $_.FullName -notlike '*\.godot\*' -and $_.FullName -notlike '*\obj\*' } |
		Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$dll = Join-Path $root 'godot\.godot\mono\temp\bin\Debug\MMOEngine.dll'
$cs = Newest (Join-Path $root 'godot')
if (-not (Test-Path $dll) -or ($cs -and $cs.LastWriteTime -gt (Get-Item $dll).LastWriteTime)) {
	Write-Host "Building the C# part ($($cs.Name) changed)..."
	& $dotnet build (Join-Path $root 'godot\MMOEngine.csproj') -c Debug -v q --nologo
} else {
	Write-Host "C# part up to date."
}
