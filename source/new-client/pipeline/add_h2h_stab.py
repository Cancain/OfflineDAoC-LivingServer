"""Hand-to-hand weapons turned to stab forward (owner 2026-10-17: "fix the fist weapons so they stab forward ... i dont
care what 0.36b does"). Run after add_h2h_held.py / add_weapon_held2.py.

For each stance-13 weapon: its blade tip (the NIF's TRAILTIP node, from the grip's origin) in grip space - through its
weapons.json "held" when it has one. When that tip is more than 35 degrees off the grip's +X (the attach bones' +X runs
down the forearm to the fingers: tests/fist_orient_probe), the shortest turn bringing it onto +X goes in front of the
grip: "held" = turn x held. A weapon with a left-hand grip ("held2", the greaves' HELD2 - the left Shield bone's +X
points back up the arm) gets "held2" = HELD2 x turn, so both hands stab forward. Fang greaves (fang hanging under the
fist), moon claws / moon fangs (blades out of the thumb side) and the mainhand slash fists were the ones off.

    python pipeline/add_h2h_stab.py
"""
import json, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif
import nif_static

LIMIT = 35.0


def tip_of(raw):
    nif = read_nif(raw)
    found = {}

    def walk(b, pm):
        if b is None:
            return
        m = nif_static.local_matrix(b) @ pm
        found[(b.get('name') or '').strip().lower()] = m[3, :3].copy()
        for c in b.get('children') or []:
            walk(c, m)
    for r in nif.roots:
        walk(r, np.identity(4))
    return found.get('trailtip')


def unpack(h):
    m = np.identity(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = h[0:3], h[3:6], h[6:9], h[9:12]
    return m


def pack(m):
    return [round(float(x), 5) for x in (*m[:3, 0], *m[:3, 1], *m[:3, 2], *m[:3, 3])]


def turn_onto_x(v):
    """The shortest rotation taking direction v onto +X."""
    a = v / np.linalg.norm(v)
    b = np.array([1.0, 0.0, 0.0])
    c = float(np.dot(a, b))
    axis = np.cross(a, b)
    s = float(np.linalg.norm(axis))
    if s < 1e-6:
        return np.diag([1.0, -1.0, -1.0]) if c < 0 else np.identity(3)   # (straight back: half a turn about Z's... Y)
    k = axis / s
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.identity(3) + kx * s + kx @ kx * (1 - c)


def main():
    path = ROOT / 'godot/content/weapons/weapons.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    done = []
    for model, w in data['models'].items():
        if int(w.get('stance', 0)) != 13 or w.get('stab'):
            continue
        src = files.get(str(w.get('nif', '')).lower() + '.nif')
        tip = tip_of(src.read_bytes()) if src else None
        if tip is None or np.linalg.norm(tip) < 1e-3:
            continue
        held = unpack(w['held']) if 'held' in w else np.identity(4)
        g = held[:3, :3] @ tip
        ang = float(np.degrees(np.arccos(np.clip(g[0] / np.linalg.norm(g), -1, 1))))
        if ang <= LIMIT:
            continue
        r = np.identity(4)
        r[:3, :3] = turn_onto_x(g)
        w['held'] = pack(r @ held)
        if 'held2' in w:
            w['held2'] = pack(unpack(w['held2']) @ r)
        w['stab'] = round(ang, 1)                  # (turned by this much - and marks it done)
        done.append((model, w['nif'], round(ang)))
    path.write_text(json.dumps(data, indent=1), encoding='utf-8')
    print(len(done), 'fist weapons turned to stab forward:')
    for d in done:
        print('  ', d)


if __name__ == '__main__':
    main()
