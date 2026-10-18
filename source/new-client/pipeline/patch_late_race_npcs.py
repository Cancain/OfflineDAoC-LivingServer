"""Points the Half Ogre / Frostalf / Shar NPC models in godot/content/monsters/monsters.json at their Catacombs race
figures (build_races.py hal_m hal_f fro_m fro_f sha_m sha_f) without a full build_monsters run: every model whose
classic figure is one of those races gets build_monsters' RACE_FIGURES prefix as its 'race' (owner 2026-10-16:
Elizabeth <Smith> drawn as one classic model with one skin over every part).

    python pipeline/patch_late_race_npcs.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT

LATE = {'bhalfogrem': 'hal_m', 'bhalfogref': 'hal_f', 'nsvartalfm': 'fro_m', 'nsvartalff': 'fro_f',
        'hsharm': 'sha_m', 'hsharf': 'sha_f'}
path = ROOT / 'godot/content/monsters/monsters.json'
data = json.loads(path.read_text(encoding='utf-8'))
models = data.get('models', data)
races = ROOT / 'godot/content/characters/races'
n = 0
for k, e in models.items():
    prefix = LATE.get(str(e.get('figure', '')).lower())
    if prefix and (races / prefix / 'figure.gltf').exists():
        e['race'] = prefix
        n += 1
path.write_text(json.dumps(data, indent=1), encoding='utf-8')   # (build_monsters' own layout)
print(n, 'models now use their race figure')
