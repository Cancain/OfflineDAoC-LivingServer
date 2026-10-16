"""Write the client's nifs.csv "Ambient Only" flag (build_zone.ambient_only) into every built zone's zone.json models,
without rebuilding the zones (owner 2026-10-14: Malmohus' pines). build_zone writes it itself from now on.

    python pipeline/apply_ambient_only.py [zone ids...]
"""
import json, sys
from pathlib import Path

import build_zone as bz
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk

ZONES = ROOT / 'godot/content/zones'


def apply(zone_id):
    zj = ZONES / f'zone{zone_id:03d}' / 'zone.json'
    dat_path = CLIENT / f'zones/zone{zone_id:03d}/dat{zone_id:03d}.mpk'
    if not dat_path.exists():                              # (the Albion epic dungeons: frontiers/zones)
        dat_path = CLIENT / f'frontiers/zones/zone{zone_id:03d}/dat{zone_id:03d}.mpk'
    if not zj.exists() or not dat_path.exists():
        return None
    dat = read_mpk(str(dat_path))
    if 'nifs.csv' not in dat:
        return None
    nifs = {int(r[0]): r for r in bz.read_csv(dat['nifs.csv']) if r and r[0].strip().isdigit()}
    z = json.loads(zj.read_text(encoding='utf-8'))
    n = 0
    for m in z.get('models', []):
        if isinstance(m.get('nif'), int) and m['nif'] in nifs:
            flag = bz.ambient_only(nifs[m['nif']])
            if m.get('ambient_only') != flag:
                m['ambient_only'] = flag
            n += flag
    zj.write_text(json.dumps(z, indent=1), encoding='utf-8')
    return n


if __name__ == '__main__':
    ids = [int(a) for a in sys.argv[1:]] or sorted(int(d.name[4:]) for d in ZONES.glob('zone[0-9][0-9][0-9]'))
    total = 0
    for zid in ids:
        n = apply(zid)
        if n is not None:
            total += n
    print(len(ids), 'zones;', total, 'ambient-only models')
