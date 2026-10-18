"""Hand-to-hand weapons gripped by their own HELD node (owner 2026-10-17: fist weapons not pointing forward). The
client always grips an in-hand item by its NIF's HELD node (game.dll 0x422806 / 0x47296a); nif_static.held_frame takes
it only for the turned-'item' structure, which left the Pict fist weapons (pict_hibernia_h2h_*, HELD turned 90 degrees
about Z over an unturned mesh) standing straight up out of the fist. For every stance-13 weapon without a "held" whose
HELD node is turned: weapons.json "held" = that grip (held_frame's format).

    python pipeline/add_h2h_held.py
"""
import json, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif
import nif_static


def held_of(raw):
    nif = read_nif(raw)
    found = []

    def walk(b, pm):
        if b is None or found:
            return
        m = nif_static.local_matrix(b) @ pm
        if (b.get('name') or '').strip().lower() == 'held':
            found.append(m)
            return
        for c in b.get('children') or []:
            walk(c, m)
    for r in nif.roots:
        walk(r, np.identity(4))
    if not found or np.allclose(found[0][:3, :3], np.identity(3), atol=1e-3):
        return None
    a = np.linalg.inv(found[0]).T
    return [round(float(x), 5) for x in (a[0, 0], a[1, 0], a[2, 0], a[0, 1], a[1, 1], a[2, 1], a[0, 2], a[1, 2], a[2, 2],
                                         a[0, 3], a[1, 3], a[2, 3])]


def main():
    path = ROOT / 'godot/content/weapons/weapons.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    done = []
    for model, w in data['models'].items():
        if int(w.get('stance', 0)) != 13 or 'held' in w:
            continue
        src = files.get(str(w.get('nif', '')).lower() + '.nif')
        h = held_of(src.read_bytes()) if src else None
        if h:
            w['held'] = h
            done.append((model, w['nif']))
    path.write_text(json.dumps(data, indent=1), encoding='utf-8')
    print(len(done), 'fist weapons now gripped by their turned HELD:', done)


if __name__ == '__main__':
    main()
