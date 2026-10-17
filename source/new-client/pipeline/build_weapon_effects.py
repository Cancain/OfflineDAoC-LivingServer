"""Weapon effects (2026-10-13, the server's 1.65 pets: the abomination's two-hander carries weapon effect 30, "univ 2h/gr
white core red glow"): an item's effect number (the equipment packets' effect field) -> spweapons.csv -> spnifs.csv ->
the effect NIF drawn on the weapon in its own space. The period set: spweapons rows 1-94, the rows the 1.64 retail
client has (the later ones are Atlantis / artifact / ToA glows). Converted like the spell effects
(build_monsters.build_effect) from DAOC_CLIENT's files; writes godot/content/weapons/weapon_effects.json
{effect: gltf path}.

    set DAOC_CLIENT=<the Claude version's client app folder>
    python pipeline/build_weapon_effects.py [--max=94]
Then repack: Godot --headless --path godot -s res://tools/pack_scenes.gd -- res://content/monsters/effects
"""
import csv, io, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from texture_index import TextureIndex
from build_zone import upscale_dir
import build_monsters

OUT = ROOT / 'godot/content/weapons/weapon_effects.json'
MAX = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--max=')), 94))

g = read_mpk(str(CLIENT / 'gamedata.mpk'))
rows = lambda n: {r[0].strip(): r for r in csv.reader(io.StringIO(g[n].decode('latin1'))) if r and r[0].strip().isdigit()}
spw, spn = rows('spweapons.csv'), rows('spnifs.csv')
idx = TextureIndex()
files = {p.name.lower(): p for p in (CLIENT / 'effects').iterdir()}
out, missing = {}, []
for k in sorted(spw, key=int):
    if int(k) > MAX:
        continue
    n = spn.get(spw[k][2].strip())
    base = n[2].strip().lower() if n else ''
    if not base or base == 'empty':
        continue
    if build_monsters.build_effect(base, idx, files):
        d = build_monsters.EFX / base
        upscale_dir(d / 'textures/original', d / 'textures/x4plus', factor_after=4)
        out[k] = f'res://content/monsters/effects/{base}/model.gltf'
    else:
        missing.append(base)
OUT.write_text(json.dumps(out, indent=1), encoding='utf-8')
print(len(out), 'weapon effects;', 'not in the client:', missing)
