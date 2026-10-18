"""Each weapon's style-trail points (owner 2026-10-17: the style colour flash "looks really delayed / slow framerate").

The client draws a style's colour trail as one ribbon swept between two nodes of the held weapon's NIF, TRAILBASE and
TRAILTIP (game.dll 0x46da71 / 0x46debd: found under "Bip01 R Hand"; no trail when a weapon has neither). Our
converted models drop empty nodes, so the points are read here from the client's NIFs, in the same model space as
the converted mesh (Godot axes, metres - nif_static), and written to godot/content/weapons/trails.json
{model id: [[base x, y, z], [tip x, y, z]]} for game/combat/style_trail.gd.

    python add_weapon_trails.py
"""
import json, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif
from nif_static import local_matrix, DAOC_TO_GODOT, UNITS_TO_METRES

OUT = ROOT / 'godot/content/weapons'


def trail_points(raw):
    nif = read_nif(raw)
    found = {}

    def walk(b, pm):
        if b is None or len(found) == 2:
            return
        m = local_matrix(b) @ pm
        name = (b.get('name') or '').strip().upper()
        if name in ('TRAILBASE', 'TRAILTIP') and name not in found:
            found[name] = [round(float(x), 5) for x in (DAOC_TO_GODOT @ m[3, :3]) * UNITS_TO_METRES]
        for c in b.get('children') or []:
            walk(c, m)
    for r in nif.roots:
        walk(r, np.identity(4))
    return [found['TRAILBASE'], found['TRAILTIP']] if len(found) == 2 else None


def main():
    models = json.loads((OUT / 'weapons.json').read_text(encoding='utf-8')).get('models', {})
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    out, cache, none = {}, {}, 0
    for model, i in models.items():
        nif = str(i.get('nif', '')).lower()
        if nif not in cache:
            p = files.get(nif + '.nif')
            try:
                cache[nif] = trail_points(p.read_bytes()) if p else None
            except Exception as e:                       # an unreadable NIF: no trail, as the client would have none
                print('skip', nif, e)
                cache[nif] = None
        if cache[nif]:
            out[model] = cache[nif]
        else:
            none += 1
    (OUT / 'trails.json').write_text(json.dumps(out), encoding='utf-8')
    print(len(out), 'weapons with a trail,', none, 'without')


if __name__ == '__main__':
    main()
