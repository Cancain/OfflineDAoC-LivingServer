"""Audit every built zone's exits (owner 2026-10-10: "make sure all the zone entrance and exit areas are working"):
the target zone / arrival, the arrival inside the target, the quad's height against the ground under it.
    python audit_exits.py   -> EXIT AUDIT.txt"""
import json, math
from collections import Counter
from assets_pipeline import ROOT

Z = ROOT / 'godot/content/zones'
zones = {int(p.name[4:]): json.loads((p / 'zone.json').read_text(encoding='utf-8'))
         for p in sorted(Z.glob('zone[0-9][0-9][0-9]')) if (p / 'zone.json').exists()}


def ground(z, x, y):
    """Terrain height (m) at zone metres x, y from the heights grid, or None (cities / dungeons)."""
    h, n = z.get('heights'), z.get('heights_size')
    if not h or not n or z.get('city'):
        return None
    if not isinstance(h, list):
        import numpy as np
        f = Z / f"zone{int(z['id']):03d}" / h
        if not f.exists():
            return None
        h = np.fromfile(f, dtype=np.float32)
    cell = z['size_m'] / (n - 1)
    i, j = min(n - 1, max(0, round(y / cell))), min(n - 1, max(0, round(x / cell)))
    return float(h[i * n + j])


rows, kinds = [], Counter()
for zid, z in zones.items():
    for e in z.get('exits', []):
        a = e.get('a') or [e['min'][0], e['min'][2]]
        b = e.get('b') or [e['max'][0], e['max'][2]]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        problems = []
        to = e.get('to_zone')
        if to is None:
            problems.append(f"no arrival (ZonePoint {e['target']} not in the old DB)")
        elif to not in zones:
            problems.append(f'target zone {to} not built')
        else:
            t = zones[to]
            px, py, pz = e['to_pos']
            if not (0 <= px <= t['size_m'] and 0 <= pz <= t['size_m']):
                problems.append(f'arrival {px:.0f},{pz:.0f} outside zone {to}')
            g = ground(t, px, pz)
            if g is not None and abs(g - py) > 6:
                problems.append(f'arrival height {py:.1f} m vs ground {g:.1f} m in zone {to}')
        g = ground(z, *mid)
        if g is not None and not (e['min'][1] - 2.5 <= g <= e['max'][1] + 2.5):
            problems.append(f"quad {e['min'][1]:.1f}-{e['max'][1]:.1f} m but the ground under it is {g:.1f} m")
        if math.dist(a, b) < 0.3:
            problems.append(f'quad only {math.dist(a, b):.2f} m wide')
        kinds['ok' if not problems else 'problem'] += 1
        rows.append((zid, z.get('name'), e['name'], e.get('label'), to, problems))
out = [f"{kinds['ok']} exits ok, {kinds['problem']} with problems ({len(zones)} built zones)\n"]
for zid, zn, name, label, to, pr in rows:
    if pr:
        out.append(f'zone {zid} {zn}: {name} ({label}) -> {to}: ' + '; '.join(pr))
(ROOT / 'EXIT AUDIT.txt').write_text('\n'.join(out) + '\n', encoding='utf-8')
print('\n'.join(out[:80]))
