"""Monster drops for every built zone (owner ruling 2026-10-09: no ROG - period drop tables; the old DB is the vetted
item source). Per monster name:
  - coins: the Uthgard bestiary's measured "bag of coins" drop rate (none known: the old server's LootGeneratorMoney,
    which always drops); the amount is the old server's formula at run time;
  - items: Uthgard's measured gear / loot drops with their rates (pipeline/data/uthgard_drops.json from
    parse_uthgard_drops.py), matched by name to the old DB's ItemTemplate (the zone's realm or realm 0 first);
  - the old server's own loot templates (MobXLootTemplate -> LootTemplate, positive chances) and one-time drops
    (LootOTD) - mostly special drops.
Writes godot/content/loot/loot.json {"drops": {name: {...}}, "items": {id: item row}} and MISSING DROP ITEMS.txt (the
Uthgard drops with no ItemTemplate of that name - to be built from Uthgard's item pages later).

    python build_loot.py"""
import json, sqlite3, sys
from collections import Counter, defaultdict
from pathlib import Path
from assets_pipeline import ROOT
from build_items import FIELDS, object_icons, global_icon, DB

OUT = ROOT / 'godot/content/loot/loot.json'
UTH = Path(__file__).parent / 'data' / 'uthgard_drops.json'


def realm_of_zone(z):
    return 1 if z < 100 else 2 if z < 200 else 3


def main():
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    uth = json.loads(UTH.read_text(encoding='utf-8'))
    by_name = defaultdict(list)
    for idn, name, realm in db.execute('select Id_nb, Name, Realm from ItemTemplate'):
        by_name[(name or '').lower()].append((idn, int(realm or 0)))
    mobx = defaultdict(list)
    for mob, tpl, cnt in db.execute('select MobName, LootTemplateName, DropCount from MobXLootTemplate'):
        mobx[(mob or '').lower()].append((tpl, int(cnt or 1)))
    tpls = defaultdict(list)
    for tpl, iid, chance, cnt in db.execute('select TemplateName, ItemTemplateID, Chance, Count from LootTemplate'):
        tpls[(tpl or '').lower()].append((iid, int(chance or 0), int(cnt or 1)))
    otd = defaultdict(list)
    for mob, iid, lvl in db.execute('select MobName, ItemTemplateID, MinLevel from LootOTD'):
        otd[(mob or '').lower()].append([iid, int(lvl or 0)])
    # every monster name in the built zones, with its zone's realm
    names = {}
    for f in sorted((ROOT / 'godot/content/zones').glob('zone*/npcs.json')):
        z = int(f.parent.name[4:])
        for s in json.loads(f.read_text(encoding='utf-8'))['spawns']:
            if int(s.get('realm') or 0) == 0:
                names.setdefault(str(s['name']).lower(), realm_of_zone(z))
    drops, used, missing = {}, set(), Counter()

    # Uthgard drops the old DB lacks (build_loot_items.py: Uthgard gear stats / vendor trash at Uthgard's sell value)
    lpath = Path(__file__).parent / 'data' / 'loot_item_rows.json'
    loot_rows = {r['Id_nb']: r for r in json.loads(lpath.read_text(encoding='utf-8'))} if lpath.exists() else {}
    loot_by_name = {r['Name'].lower(): r['Id_nb'] for r in loot_rows.values()}

    def resolve(item_name, realm):
        rows = by_name.get(item_name.lower(), [])
        for want in (realm, 0):
            for idn, r in rows:
                if r == want:
                    return idn
        return rows[0][0] if rows else loot_by_name.get(item_name.lower())

    for name, realm in names.items():
        d = {'coins': None, 'items': [], 'otd': otd.get(name, [])}
        u = uth.get(name)
        if u:
            d['coins'] = u.get('coins')
            for item_name, rate in u['items']:
                iid = resolve(item_name, realm)
                if iid:
                    d['items'].append([iid, rate])
                    used.add(iid)
                else:
                    missing[item_name] += 1
        for tpl, cnt in mobx.get(name, []):                  # the server's own templates (positive chances)
            for iid, chance, c in tpls.get((tpl or '').lower(), []):
                if chance > 0 and not any(x[0] == iid for x in d['items']):
                    d['items'].append([iid, float(chance)])
                    used.add(iid)
        for iid, _lvl in d['otd']:
            used.add(iid)
        d['source'] = 'uthgard' if u else ('server templates' if d['items'] else 'none')
        drops[name] = d
    icons = object_icons()
    cols = ', '.join(FIELDS)
    items = {}
    # drops the old DB names but has no item for (build_drop_items.py: period / Uthgard / Allakhazam pages, or made up)
    extra_path = Path(__file__).parent / 'data' / 'drop_item_rows.json'
    extra = {r['Id_nb']: r for r in json.loads(extra_path.read_text(encoding='utf-8'))} if extra_path.exists() else {}
    for iid in sorted(used):
        row = db.execute(f'select Id_nb, {cols} from ItemTemplate where Id_nb=?', (iid,)).fetchone()
        if row is None and (iid in extra or iid in loot_rows):
            pr = extra.get(iid) or loot_rows[iid]
            row = tuple([iid] + [pr.get(f, 0 if f not in ('Name', 'AllowedClasses') else '') for f in FIELDS])
        if row is None:
            continue
        it = dict(zip(['id'] + [f.lower() for f in FIELDS], row))
        it['icon'] = global_icon(icons.get(int(it['model'] or 0), -1))
        items[iid] = it
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({'drops': drops, 'items': items, 'money': {'formula': 'LootGeneratorMoney', 'money_drop': 1.0},
                               'source': 'Uthgard bestiary drop rates (period-data, read only) + old DB templates / OTD'},
                              indent=1), encoding='utf-8')
    (ROOT / 'MISSING DROP ITEMS.txt').write_text(
        'Uthgard drops still without an item (count = monster types that drop it). Everything else is built by\n'
        'build_loot_items.py (Uthgard gear / vendor trash). Left out on purpose: "small chest" / "large chest"\n'
        "(Uthgard's random-item containers - no ROG) and the coin entries (coins drop by their own rule).\n\n" +
        '\n'.join(f'{c:4d}  {n}' for n, c in missing.most_common()), encoding='utf-8')
    src = Counter(d['source'] for d in drops.values())
    print(len(drops), 'monster names:', dict(src), '|', len(items), 'items |', len(missing), 'item names missing')


if __name__ == '__main__':
    main()
