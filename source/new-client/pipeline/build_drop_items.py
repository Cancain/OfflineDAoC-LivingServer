"""Monster drops whose item the old DB doesn't have (owner 2026-10-10: "invent stats for the items or make them vendor
trash if they are not equipment or for a quest"). The old server's loot templates / one-time drops name 25 items with
no ItemTemplate row - every one is equipment from a named boss (Golestandt, Xanxicar, Scurceol Hyrde, Dura'ek,
Weno'iak, Sys'sro, Maldahar). The same sources and rules as the quest rewards (build_reward_items.py):
  1. period Allakhazam page, 2. Uthgard page, 3. today's Allakhazam (post-1.65 bonus kinds dropped, held to the period
     ceiling of its level), 4. none: stats made up to fit (the item level from the boss: 50) - listed in
     "1.65 EXCEPTIONS MADE.txt".
Writes pipeline/data/drop_item_rows.json + drop_items_report.json; build_loot.py takes these rows for ids the DB lacks.
    python build_drop_items.py      (then python build_loot.py)"""
import json, re
from pathlib import Path
import build_reward_items as b

HERE = Path(__file__).resolve().parent
OUT_ROWS = HERE / 'data/drop_item_rows.json'
OUT_REPORT = HERE / 'data/drop_items_report.json'
# no page anywhere: (item type, object type, a stat or skill the name promises, realm)
INVENT = {
    'Fairich Sgath Bracer': (33, 41, None, 'hibernia'),
    'Ring_of_Pumice': (35, 41, None, 'albion'),
    "Sys'sro's Belt of Parry": (32, 41, 40, 'albion'),         # "of Parry": the parry skill
    "Weno'iak Belt": (32, 41, None, 'albion'),
    "Weno'iak Jewel": (24, 41, None, 'albion'),
    "Weno'iak's Pendant": (29, 41, None, 'albion'),
    "Weno'iak's Ring": (35, 41, None, 'albion'),
}
ITEM_LEVEL = 50                                           # drops of level 68-81 raid bosses: the top item level
REALM_OF = {'golestandt': 'albion', 'moran the mighty': 'albion', 'xanxicar': 'albion', 'scurceol hyrde': 'albion',
            "dura'ek the empowered": 'albion', "sys'sro the ruthless": 'albion', "weno'iak the enlightened": 'albion',
            'maldahar the glimmer prince': 'hibernia'}


def main():
    import sqlite3
    loot = json.loads((b.ROOT / 'godot/content/loot/loot.json').read_text(encoding='utf-8'))
    missing = {}
    for mob, d in loot['drops'].items():
        for kind in ('items', 'otd'):
            for e in d[kind]:
                if e[0] not in loot['items']:
                    missing.setdefault(e[0], set()).add(mob)
    pages = b.load_pages()
    db = sqlite3.connect(f'file:{b.DB}?mode=ro', uri=True)
    model, spell = b.borrowers(db)
    reward_rows = json.loads((HERE / 'data/reward_item_rows.json').read_text(encoding='utf-8'))
    reward_rep = json.loads((HERE / 'data/reward_items_report.json').read_text(encoding='utf-8'))['built']
    period_rows = [r for r in reward_rows if reward_rep.get(r['Id_nb'], {}).get('source') in ('period', 'uthgard')]
    cls_names = {v: k[1] for k, v in b.CLASS_IDS.items()}
    rows, report = [], {}
    order = {'period': 0, 'uthgard': 1, 'live': 2}
    for iid, mobs in sorted(missing.items()):
        name = iid.replace('_', ' ')
        realm = REALM_OF.get(sorted(mobs)[0], 'albion')
        need = {'id': iid, 'name': name, 'realm': realm}
        cands = sorted({id(p): p for v in b.name_variants(name) for p in pages.get(v, [])}.values(), key=lambda p: order[p['kind']])
        built = None
        for p in cands:
            row, unknown, has_stats = b.parse(p, need)
            if has_stats:
                built = (p, row, unknown)
                break
        notes = []
        if built:
            p, row, unknown = built
            row.update(Id_nb=iid, Name=name)
            rc = b.field(p['text'], 'Requires Class:') if p['kind'] != 'uthgard' else None
            if rc:
                ids = [str(b.CLASS_IDS[(row['Realm'], c.strip().lower())]) for c in re.split(r'\s*,\s*', rc)
                       if (row['Realm'], c.strip().lower()) in b.CLASS_IDS]
                if ids:
                    row['AllowedClasses'] = ';'.join(ids)
            row['Model'] = model(row['Item_Type'], row['Object_Type'], row['Realm'], row['Level'])
            notes.append(f"model {row['Model']} borrowed")
            sid, why = spell(p['text']) if p['kind'] != 'uthgard' else (None, None)
            if sid:
                charges = int(b.num(b.field(p['text'], 'Charges:')))
                if charges or row['Item_Type'] in (24, 26, 29, 32, 33, 35) or row['Object_Type'] in (0, 41):
                    row.update(SpellID=sid, Charges=charges or 10, MaxCharges=charges or 10)
                else:
                    row.update(ProcSpellID=sid, ProcChance=0)
                notes.append(why)
            if unknown:
                notes.append('bonuses with no server property: ' + '; '.join(unknown))
            if p['kind'] == 'live':
                b.sanitize_live(row, period_rows, notes)
            report[iid] = {'name': name, 'source': p['kind'], 'page': p['url'], 'dropped_by': sorted(mobs), 'notes': notes}
        else:
            it, ot, stat, realm = INVENT[iid]
            skill = stat if stat and stat > 19 else None
            row, notes = b.invent(iid, name, realm, ITEM_LEVEL, [], it, ot, stat if stat and stat <= 19 else None, None,
                                  0, period_rows, model, pages, cls_names)
            if skill:                                        # the skill its name promises, at the level's cap
                bon = b.bonus_list(row)
                if skill not in [t for t, _ in bon]:
                    bon.insert(0, (skill, b.cap_of(skill, ITEM_LEVEL)))
                    b.set_bonuses(row, bon[:10])
                    notes.append(f'skill {skill} from the name')
            report[iid] = {'name': name, 'source': 'invented', 'dropped_by': sorted(mobs), 'notes': notes}
        rows.append(row)
    OUT_ROWS.write_text(json.dumps(rows, indent=1), encoding='utf-8')
    OUT_REPORT.write_text(json.dumps(report, indent=1), encoding='utf-8')
    from collections import Counter
    print(len(rows), 'drop items:', dict(Counter(v['source'] for v in report.values())))


if __name__ == '__main__':
    main()
