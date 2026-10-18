"""Each weapon's left-hand grip, HELD2, into content/weapons/weapons.json as "held2" (owner 2026-10-17: the Savage's
claws held wrong in the off hand). game.dll 0x47296a: attaching an item to a bone whose name holds "L Held" or
"L Shield", the client grips it by its NIF's HELD2 node instead of HELD when it has one - the hand-to-hand claws /
greaves carry HELD2 turned 180 degrees about Y, so the left claw faces the other way. Stored in held_frame's format
(column-vector hand <- model, NIF axes: [basis x, y, z, origin]); left out when HELD2 is the identity.

    python pipeline/add_weapon_held2.py [--dry]
"""
import json, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif
import nif_static


def held2_frame(raw):
    nif = read_nif(raw)
    found = []

    def walk(b, pm):
        if b is None or found:
            return
        m = nif_static.local_matrix(b) @ pm
        if (b.get('name') or '').strip().upper() == 'HELD2':
            found.append(m)
            return
        for c in b.get('children') or []:
            walk(c, m)
    for r in nif.roots:
        walk(r, np.identity(4))
    if not found or np.allclose(found[0], np.identity(4), atol=1e-3):
        return None
    a = np.linalg.inv(found[0]).T                          # row-vector model -> grip, as hand <- model (column vectors)
    return [round(float(x), 5) for x in (a[0, 0], a[1, 0], a[2, 0], a[0, 1], a[1, 1], a[2, 1], a[0, 2], a[1, 2], a[2, 2],
                                         a[0, 3], a[1, 3], a[2, 3])]


def main():
    path = ROOT / 'godot/content/weapons/weapons.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    cache, done, shields = {}, [], []
    for model, w in data['models'].items():
        nif = str(w.get('nif', '')).lower()
        if nif not in cache:
            src = files.get(nif + '.nif')
            try:
                cache[nif] = held2_frame(src.read_bytes()) if src else None
            except Exception as e:
                print('skip', nif, e)
                cache[nif] = None
        h = cache[nif]
        if h:
            w['held2'] = h
            done.append(model)
            if int(w.get('shield', 0)) > 0:
                shields.append(model)
        else:
            w.pop('held2', None)
    if '--dry' not in sys.argv:
        path.write_text(json.dumps(data, indent=1), encoding='utf-8')
    print(len(done), 'weapons with a turned HELD2;', len(shields), 'of them shields', shields[:20])
    print('e.g.', done[:30])


if __name__ == '__main__':
    main()
