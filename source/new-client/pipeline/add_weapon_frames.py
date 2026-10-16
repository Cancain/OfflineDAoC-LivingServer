"""Add each weapon's HELD frame (nif_static.held_frame) to content/weapons/weapons.json without re-converting the
weapons (2026-10-13; build_weapons.py records it from now on).

    set DAOC_CLIENT=<the Claude version's client app folder>
    python pipeline/add_weapon_frames.py
"""
import json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
import nif_static

path = ROOT / 'godot/content/weapons/weapons.json'
data = json.loads(path.read_text(encoding='utf-8'))
files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
done = []
for model, w in data['models'].items():
    src = files.get(str(w.get('nif', '')).lower() + '.nif')
    if src is None:
        continue
    held = nif_static.held_frame(src.read_bytes())
    if held:
        w['held'] = held
        done.append(f"{model} {w['nif']}")
    else:
        w.pop('held', None)
path.write_text(json.dumps(data, indent=1), encoding='utf-8')
print(len(done), 'weapons with a turned grip:', done)
