"""Write the dungeons' own fog / sky colours (sector.dat) into already built dungeon zones (build_zone.py does it on a
rebuild).   python patch_dungeon_fog.py"""
import json
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from build_zone import sector_ini, dungeon_fog

for zj in sorted((ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]/zone.json')):
    z = json.loads(zj.read_text(encoding='utf-8'))
    if not z.get('dungeon'):
        continue
    zid = int(z['id'])
    f = CLIENT / 'zones' / f'zone{zid:03d}' / f'dat{zid:03d}.mpk'
    if not f.exists():
        f = CLIENT / 'frontiers/zones' / f'zone{zid:03d}' / f'dat{zid:03d}.mpk'
    if not f.exists():
        continue
    sector = sector_ini(read_mpk(str(f))['sector.dat'])
    z['fog'] = dungeon_fog(sector)
    z['sky'] = [sector.getint('sky', c, fallback=0) / 255.0 for c in ('red', 'green', 'blue')]
    zj.write_text(json.dumps(z, indent=1), encoding='utf-8')
    print(zid, z['name'], 'fog', [round(c * 255) for c in z['fog']['color']], z['fog']['amount'], round(z['fog']['clip_m']), 'm  sky', [round(c * 255) for c in z['sky']])
