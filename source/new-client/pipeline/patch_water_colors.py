"""Fill water base colours into already built zones (build_zone.py now writes them on a rebuild).
    python patch_water_colors.py"""
import json, re, configparser
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from build_zone import water_base_color
import glob
for zj in sorted((ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]/zone.json')):
    z = json.loads(zj.read_text(encoding='utf-8'))
    if not any(not w.get('texture') for w in z.get('water', [])):
        continue
    zid = int(z['id'])
    sector = None
    for f in glob.glob(str(CLIENT / 'zones' / f'zone{zid:03d}' / '*.mpk')):
        m = read_mpk(f)
        if 'sector.dat' in m:
            sector = m['sector.dat'].decode('latin1')
            break
    if sector is None:
        continue
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.read_string(re.sub(r'(?m)^[^\[\n=]*$', '', sector))
    n = 0
    for w in z['water']:
        sec = f"river{int(w['id']):02d}"
        if cp.has_section(sec):
            w['base_color'] = water_base_color(cp[sec])
            n += 1
    zj.write_text(json.dumps(z, indent=1), encoding='utf-8')
    print(zid, z['name'], n, [w.get('base_color') for w in z['water'] if not w.get('texture')][:2])
