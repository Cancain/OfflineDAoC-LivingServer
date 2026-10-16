"""Move the floating server props (build_zone.WORLD_OBJECT_DROP) down / drop the WORLD_OBJECT_SKIP ones in already built zones (build_zone.py does it
on a rebuild). Safe to run again: it sets the height from the old DB's Z, it doesn't subtract twice.
    python patch_prop_drops.py"""
import json, sqlite3
from assets_pipeline import ROOT
from build_zone import WORLD_OBJECT_DROP, WORLD_OBJECT_SKIP, OLD_DB, M, zone_section

con = sqlite3.connect(f'file:{OLD_DB.as_posix()}?mode=ro', uri=True)
for zj in sorted((ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]/zone.json')):
    z = json.loads(zj.read_text(encoding='utf-8'))
    zid = int(z['id'])
    sec = dict(l.split('=', 1) for l in zone_section(zid).splitlines() if '=' in l)
    sec = {k.strip().lower(): v.strip() for k, v in sec.items()}
    region = int(sec.get('region', zid))
    ox, oy = int(sec.get('region_offset_x', 0)) * 8192, int(sec.get('region_offset_y', 0)) * 8192
    n = 0
    for (r, name, x, y), gap in WORLD_OBJECT_DROP.items():
        if r != region:
            continue
        row = con.execute('select Z from WorldObject where Region=? and Name=? and abs(X-?)<4 and abs(Y-?)<4',
                          (r, name, x, y)).fetchone()
        if row is None:
            continue
        want = (row[0] - round((gap + 0.1) * 40)) * M
        for p in z.get('fixtures', []):
            if p.get('source') in ('world_object', 'world_object_effect') and p['name'] in (name, f'{name} effect') \
                    and abs(p['pos'][0] - (x - ox) * M) < 0.2 and abs(p['pos'][2] - (y - oy) * M) < 0.2:
                p['pos'][1] = want
                n += 1
    for (r, name, x, y) in WORLD_OBJECT_SKIP:
        if r != region:
            continue
        keep = [p for p in z.get('fixtures', []) if not (p.get('source') in ('world_object', 'world_object_effect')
                and p['name'] in (name, f'{name} effect') and abs(p['pos'][0] - (x - ox) * M) < 0.2
                and abs(p['pos'][2] - (y - oy) * M) < 0.2)]
        n += len(z['fixtures']) - len(keep)
        z['fixtures'] = keep
    if n:
        zj.write_text(json.dumps(z, indent=1), encoding='utf-8')
        print(zid, z.get('name'), n, 'props moved down')
