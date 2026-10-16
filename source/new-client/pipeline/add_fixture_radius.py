"""Adds fixtures.csv's Radius to the fixtures of already built zones (build_zone writes it from now on), without a
rebuild: the client gives a fixture it doesn't collide with (trees) but gives a Radius an invisible upright box wall
around its trunk (game.dll 0x49084e, ZoneLoader.proxy_faces; owner 2026-10-11: bots walked up the Myrkwood pines).
The zone's own fixture rows are matched in build_zone's order (rows whose NIF has a model), checked by id and name.
Then re-export the host's collision: Godot --headless --path godot -s res://tools/export_world_collision.gd"""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from build_zone import read_csv, fixture_radius

ZONES = ROOT / 'godot/content/zones'


def main():
    done = 0
    for zj in sorted(ZONES.glob('zone*/zone.json')):
        zid = int(zj.parent.name[4:])
        dat_path = CLIENT / f'zones/zone{zid:03d}/dat{zid:03d}.mpk'
        if not dat_path.exists():
            continue
        dat = read_mpk(str(dat_path))
        if 'fixtures.csv' not in dat:
            continue
        info = json.loads(zj.read_text())
        rows = [r for r in read_csv(dat['fixtures.csv'])[2:] if len(r) > 11 and r[1].strip().isdigit()]
        mine = [f for f in info['fixtures'] if f.get('source') is None and int(f.get('id', -1)) >= 0 and 'basis' not in f]
        it = iter(mine)
        matched, bad = 0, 0
        cur = next(it, None)
        for r in rows:
            if cur is None:
                break
            if int(r[0]) != int(cur['id']) or r[2].strip() != cur['name']:
                continue                                  # a row whose NIF had no model (build_zone skipped it)
            cur['radius'] = fixture_radius(r)
            matched += 1
            cur = next(it, None)
        bad = len(mine) - matched
        zj.write_text(json.dumps(info))
        with_r = sum(1 for f in mine if f.get('radius', 0) > 0 and not f.get('collide'))
        print(f'zone {zid:3d} {info["name"][:24]:24} fixtures {len(mine):5}  matched {matched:5}  unmatched {bad:3}  '
              f'tree boxes {with_r:5}')
        done += 1
    print(done, 'zones')


if __name__ == '__main__':
    main()
