"""Re-run the NIF converter on every converted effect (content/monsters/effects/<nif>) - after a converter change
(2026-10-11: environment maps and colour animations) - and upscale any new textures.

    set DAOC_CLIENT=<the Claude version's client app folder>   (the Sluaghbinder's custom effect NIFs live there)
    python pipeline/reconvert_effects.py
Then repack: Godot --headless --path godot -s res://tools/pack_scenes.gd -- --force res://content/monsters/effects
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.argv.append('--reconvert-effects')
from assets_pipeline import CLIENT
from texture_index import TextureIndex
from build_zone import upscale_dir
import build_monsters

idx = TextureIndex()
files = {p.name.lower(): p for p in (CLIENT / 'effects').iterdir()}
done, missing = 0, []
for d in sorted(p for p in build_monsters.EFX.iterdir() if p.is_dir()):
    if build_monsters.build_effect(d.name, idx, files):
        done += 1
        upscale_dir(d / 'textures/original', d / 'textures/x4plus', factor_after=4)
    else:
        missing.append(d.name)
print(done, 'effects reconverted; not in the client:', missing[:20])
