"""Rewrite the exits of already built zones from build_zone.zone_exits (real quad ends 'a' / 'b', arrivals) - a
rebuild writes the same.   python patch_exits.py"""
import json
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from build_zone import zone_exits

for zj in sorted((ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]/zone.json')):
    z = json.loads(zj.read_text(encoding='utf-8'))
    zid = int(z['id'])
    f = CLIENT / 'zones' / f'zone{zid:03d}' / f'dat{zid:03d}.mpk'
    if not f.exists():
        f = CLIENT / 'frontiers/zones' / f'zone{zid:03d}' / f'dat{zid:03d}.mpk'
    if not f.exists() or not z.get('exits'):
        continue
    old = len(z['exits'])
    z['exits'] = zone_exits(read_mpk(str(f)))
    zj.write_text(json.dumps(z, indent=1), encoding='utf-8')
    print(zid, z.get('name'), old, '->', len(z['exits']), 'exits,', sum(1 for e in z['exits'] if 'to_zone' in e), 'with arrivals')
