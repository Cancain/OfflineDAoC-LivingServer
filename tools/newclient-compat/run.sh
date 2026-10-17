#!/bin/bash
# Runs the new-client check (README.md). Arguments: <Godot 4.7.2 .NET folder> <copy of source/new-client/godot>
set -e
GODOT_DIR=${1:?Godot 4.7.2 .NET folder}
CLIENT=${2:?a copy of source/new-client/godot (it gets placeholder art and the probe)}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mktemp -d)
cp "$HERE/living_server_probe.gd" "$CLIENT/tests/"
python3 "$HERE/placeholders.py" "$CLIENT"
dotnet build "$HERE/FakeServer.csproj" -c Release -o "$OUT/server" > /dev/null
(cd "$CLIENT" && dotnet build MMOEngine.csproj > /dev/null)
dotnet "$OUT/server/FakeServer.dll" "$OUT" > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 3
GODOT=$(ls "$GODOT_DIR"/Godot_v*_mono_linux.x86_64 "$GODOT_DIR"/Godot_v*_mono_win64.exe 2>/dev/null | head -1)
"$GODOT" --headless --path "$CLIENT" -s res://tests/living_server_probe.gd > "$OUT/probe.log" 2>&1 || true
wait $SERVER || true
USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/MMOEngine"
cp "$USERDIR/living_server_probe.json" "$OUT/"
python3 "$HERE/compare.py" "$OUT"
