"""Stable master horse routes (GameStableMaster / GameTaxi): every ticket a built merchant list sells (an item whose
Id_nb names a Path) -> its path in REGION units (routes run across zone borders), its type, its region, the mount
(the ticket's Color = an NpcTemplate: its model and size; 0 = the "horse" NPC standing by the stable). Writes
godot/content/world/routes.json.

    python build_routes.py"""
import json, sqlite3
from assets_pipeline import ROOT
OLD = ROOT / 'external/old_project'
DB = OLD / 'runtime/data/opendaoc.sqlite3.db'


def main():
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    merchants = json.loads((ROOT / 'godot/content/items/merchants.json').read_text(encoding='utf-8'))
    ids = {row[2] for lst in merchants['lists'].values() for row in lst}
    out = {}
    for pid in sorted(ids):
        it = db.execute('select Name, Color, Item_Type from ItemTemplate where Id_nb=?', (pid,)).fetchone()
        p = db.execute('select PathType, RegionID from Path where PathID=?', (pid,)).fetchone()
        if not it or not p or int(it[2] or 0) != 40:
            continue
        # horses, and the Shrouded Isles' faction flights (dragonfly / wyvern / gryphon: patch 1.65 added Inishail
        # Island, Modernagrav and Allta Fearann with them); the SI boats come separately
        fly = pid.lower().startswith(('dragonfly_', 'wyvern_', 'gryphon_'))
        if not (fly or pid.lower().startswith(('hs_', 'hr_'))):
            continue
        pts = [[int(x), int(y), int(z), int(sp or 0), int(w or 0)] for x, y, z, sp, w in
               db.execute('select X, Y, Z, MaxSpeed, WaitTime from PathPoints where PathID=? order by Step', (pid,))]
        if len(pts) < 2:
            continue
        mount = {}
        if int(it[1] or 0) > 0:
            t = db.execute('select Model, Size, Name from NpcTemplate where TemplateId=?', (int(it[1]),)).fetchone()
            if t:
                mount = {'model': int(str(t[0]).split(';')[0].split(',')[0] or 0), 'size': int(str(t[1] or 50).split(';')[0].split(',')[0] or 50),
                         'name': t[2]}
        out[pid] = {'name': it[0], 'type': int(p[0] or 1), 'region': int(p[1] or 0), 'mount': mount, 'points': pts}
        if fly:                                           # flights follow the path's heights, not the ground
            out[pid]['fly'] = True                        # ...and the rider sits the anims.csv "Ride X" pose
            out[pid]['ride_clip'] = {'dragonfly_': 'ride_dragonfly', 'wyvern_': 'ride_amphitere',
                                     'gryphon_': 'ride_griffon'}[pid.lower().split('_')[0] + '_']
    dest = ROOT / 'godot/content/world/routes.json'
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps({'routes': out, 'speed': 1500, 'start_within': 500,
                                'source': 'old DB Path / PathPoints / ItemTemplate (tickets), GameStableMaster'}, indent=1),
                    encoding='utf-8')
    print(len(out), 'routes;', sum(1 for r in out.values() if r.get('fly')), 'flights;', sum(1 for r in out.values() if r['mount']), 'with a template mount')


if __name__ == '__main__':
    main()
