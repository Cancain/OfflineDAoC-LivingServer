"""Fill an already built zone.json's empty 'spots' with the old ZonePoint arrivals (build_zone.entrance_spots), without
rebuilding the zone.  python zone_spots_fill.py 201 202 ...   (no ids: every built zone with no spots)"""
import json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT
from build_zone import entrance_spots


def main():
    zones = [int(a) for a in sys.argv[1:] if a.isdigit()]
    if not zones:
        zones = sorted(int(p.name[4:]) for p in (ROOT / 'godot/content/zones').glob('zone*') if p.name[4:].isdigit())
    for z in zones:
        f = ROOT / f'godot/content/zones/zone{z:03d}/zone.json'
        if not f.exists():
            continue
        d = json.loads(f.read_text(encoding='utf-8'))
        if d.get('spots'):
            continue
        d['spots'] = entrance_spots(z)
        f.write_text(json.dumps(d), encoding='utf-8')
        print(z, d.get('name'), len(d['spots']), 'spots', [s['name'] for s in d['spots']][:5])


if __name__ == '__main__':
    main()
