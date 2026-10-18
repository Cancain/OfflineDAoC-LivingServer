"""Refresh only the 'exits' of the built zones from the client's zonejump.csv - its csvNNN.mpk copy first
(build_zone.client_zonejump; owner 2026-10-17: the Tuscaran Glacier zone-in spot in Delling Crater was missing),
without rebuilding the zones. Prints each zone whose exits change.

    python patch_zone_exits.py
"""
import json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
import build_zone


def main():
    for zj in sorted((ROOT / 'godot/content/zones').glob('zone*/zone.json')):
        zid = int(zj.parent.name[4:])
        zdir = CLIENT / f'zones/zone{zid:03d}'
        if not zdir.exists():
            zdir = CLIENT / f'frontiers/zones/zone{zid:03d}'
        jump = build_zone.client_zonejump(zdir, zid)
        if jump is None:
            continue
        zone = json.loads(zj.read_text(encoding='utf-8'))
        old = zone.get('exits', [])
        new = build_zone.zone_exits({'zonejump.csv': jump})
        if json.dumps(old, sort_keys=True) == json.dumps(new, sort_keys=True):
            continue
        before = sorted({int(e.get('target', 0)) for e in old})
        after = sorted({int(e.get('target', 0)) for e in new})
        print(f'zone {zid} {zone.get("name")}: exits {len(old)} -> {len(new)}, targets {before} -> {after}')
        zone['exits'] = new
        zj.write_text(json.dumps(zone, indent=1), encoding='utf-8')


if __name__ == '__main__':
    main()
