"""The helm-hair morphs of every race figure's hair styles into its figure.json (0.36c, owner 2026-10-11: hair poked
through the hat). Each hair mesh carries morph targets with negative feature codes -1 / -2 / -3: the shape the hair
takes under a helm of that 'Cata Helm Hair' type (items.csv column 23 of the helm's Catacombs NIF). Read from the
built figure.gltf (mesh extras 'codes' / 'targetNames'): figure.json 'helm_hair' = {hair node: {"1": target, ...}}.

    python pipeline/add_helm_hair_morphs.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / 'godot/content/characters/races'

for d in sorted(p for p in ROOT.iterdir() if (p / 'figure.gltf').exists()):
    g = json.loads((d / 'figure.gltf').read_text(encoding='utf-8'))
    out = {}
    for n in g['nodes']:
        if not n.get('name', '').startswith('hair_') or 'mesh' not in n:
            continue
        ex = g['meshes'][n['mesh']].get('extras', {})
        names, codes = ex.get('targetNames', []), ex.get('codes', [])
        m = {str(-c): names[i] for i, c in enumerate(codes) if c < 0 and i < len(names)}
        if m:
            out[n['name']] = m
    meta = json.loads((d / 'figure.json').read_text(encoding='utf-8'))
    meta['helm_hair'] = out
    (d / 'figure.json').write_text(json.dumps(meta, indent=1), encoding='utf-8')
    print(d.name, len(out), 'hair styles with helm morphs')
