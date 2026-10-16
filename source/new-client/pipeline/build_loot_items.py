"""The Uthgard drops the old DB has no item for (MISSING DROP ITEMS.txt, ~1800 names; owner 2026-10-10: "invent stats
for the items or make them vendor trash if they are not equipment or for a quest"):
  - an Uthgard item page with a slot (gear): its stats (build_reward_items.parse), the model borrowed;
  - an Uthgard page without a slot ("Item": gems, food, parts): vendor trash at its Uthgard sell value (Price = 2x,
    merchants pay 50%), the model of an old-DB loot item sharing a word with it (opal, claw, hide, dust ...);
  - only today's Allakhazam: gear from it under the 1.65 check (build_reward_items.sanitize_live);
  - no page anywhere: vendor trash priced at the median Uthgard sell value of what the same monsters drop;
  - left out: "small chest" / "large chest" (Uthgard's random-item containers - no ROG, owner) and the coin entries
    (coins drop by their own rule).
Writes pipeline/data/loot_item_rows.json (+ report); build_loot.py resolves drop names to these when the DB has none.
    python build_loot_items.py      (then python build_loot.py)"""
import json, re, sqlite3, statistics
from collections import Counter, defaultdict
from pathlib import Path
import build_reward_items as b

HERE = Path(__file__).resolve().parent
OUT_ROWS = HERE / 'data/loot_item_rows.json'
OUT_REPORT = HERE / 'data/loot_items_report.json'
SKIP = {'small chest', 'large chest', 'some copper coins', 'copper coin'}
GEMS = ('opal', 'sapphire', 'spinel', 'tourmaline', 'garnet', 'diamond', 'emerald', 'topaz', 'beryl', 'jasper', 'agate',
        'zircon', 'obsidian', 'lapis', 'malachite', 'heliodor', 'azurite', 'kunzite', 'citrine', 'sunstone', 'pearl',
        'jacinth', 'bloodstone', 'carnelian', 'chryoprase', 'chrysoprase', 'diopside', 'apatite', 'sphene', 'amethyst',
        'ruby', 'onyx', 'jade', 'chrysoberyl', 'enamel')


def copper(text):
    total = 0
    for n, u in re.findall(r'(\d+)\s*([pgsc])\b', text or ''):
        total += int(n) * {'p': 10_000_000, 'g': 10_000, 's': 100, 'c': 1}[u]
    return total


def slug(name):
    return 'uth_' + re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')[:60]


def main():
    names = []
    for line in (b.ROOT / 'MISSING DROP ITEMS.txt').read_text(encoding='utf-8').splitlines()[3:]:
        m = re.match(r'\s*(\d+)\s+(.+)$', line)
        if m and m.group(2).strip().lower() not in SKIP:
            names.append(m.group(2).strip())
    pages = b.load_pages()
    db = sqlite3.connect(f'file:{b.DB}?mode=ro', uri=True)
    model, spell = b.borrowers(db)
    # old-DB loot items by word -> their most common model (the borrowed look for vendor trash)
    word_models = defaultdict(Counter)
    for name, mdl in db.execute('select Name, Model from ItemTemplate where Item_Type in (0, 40) and Model > 0'):
        for w in re.findall(r'[a-z]+', (name or '').lower()):
            if len(w) > 3:
                word_models[w][int(mdl)] += 1
    gem_model = word_models['opal'].most_common(1)[0][0] if word_models['opal'] else 115

    def trash_model(name):
        words = re.findall(r'[a-z]+', name.lower())
        if any(g in words for g in GEMS):
            return gem_model
        for w in reversed(words):
            if w in word_models and len(w) > 3:
                return word_models[w].most_common(1)[0][0]
        return 488
    reward_rows = json.loads((HERE / 'data/reward_item_rows.json').read_text(encoding='utf-8'))
    reward_rep = json.loads((HERE / 'data/reward_items_report.json').read_text(encoding='utf-8'))['built']
    period_rows = [r for r in reward_rows if reward_rep.get(r['Id_nb'], {}).get('source') in ('period', 'uthgard')]
    uth = json.loads((HERE / 'data/uthgard_drops.json').read_text(encoding='utf-8'))
    rows, report, priced = [], {}, {}

    def trash(iid, name, price, why):
        rows.append(dict(Id_nb=iid, Name=name, Level=0, Durability=0, MaxDurability=0, Condition=50000, MaxCondition=50000,
                         Quality=100, DPS_AF=0, SPD_ABS=0, Hand=0, Type_Damage=0, Object_Type=0, Item_Type=40, Weight=5,
                         Bonus=0, BonusLevel=0, Realm=0, AllowedClasses='0', IsPickable=1, IsDropable=1, IsTradable=1,
                         Price=price, MaxCount=1, PackSize=1, Color=0, Extension=0, Model=trash_model(name)))
        report[iid] = {'name': name, 'kind': 'vendor trash', 'price': price, 'why': why}

    later = []
    for name in names:
        iid = slug(name)
        cands = [p for v in b.name_variants(name) for p in pages.get(v, [])]
        ut = next((p for p in cands if p['kind'] in ('period', 'uthgard')), None)
        live = next((p for p in cands if p['kind'] == 'live'), None)
        if ut is not None:
            slot = (re.search(r'\bSlot (\w+)', ut['text']) or [None, ''])[1].lower()
            sell = copper((re.search(r'Sell value\s+((?:\d+[pgsc]\s*)+)', ut['text']) or [None, ''])[1])
            if slot in ('', 'item') or not slot:
                trash(iid, name, sell * 2, 'Uthgard sell value')
                priced[name.lower()] = sell
                continue
            row, unknown, has_stats = b.parse(ut, {'id': iid, 'name': name, 'realm': ''})
            row.update(Id_nb=iid, Name=name, Price=max(row.get('Price', 0), sell * 2), IsTradable=1)
            row['Model'] = model(row['Item_Type'], row['Object_Type'], row['Realm'], row['Level'])
            rows.append(row)
            report[iid] = {'name': name, 'kind': 'gear (Uthgard)', 'page': ut['url'], 'unknown': unknown}
            priced[name.lower()] = sell
        elif live is not None:
            row, unknown, has_stats = b.parse(live, {'id': iid, 'name': name, 'realm': ''})
            notes = []
            if not has_stats or row['Item_Type'] == 40:
                later.append(name)
                continue
            row.update(Id_nb=iid, Name=name, IsTradable=1)
            row['Model'] = model(row['Item_Type'], row['Object_Type'], row['Realm'], row['Level'])
            b.sanitize_live(row, period_rows, notes)
            rows.append(row)
            report[iid] = {'name': name, 'kind': "gear (today's Allakhazam)", 'page': live['url'], 'notes': notes}
        else:
            later.append(name)
    # no page: the median sell value of the priced loot the same monsters drop
    by_item_mobs = defaultdict(list)
    for mob, d in uth.items():
        for item, _rate in d.get('items', []):
            by_item_mobs[item.lower()].append(mob)
    for name in later:
        vals = [priced[i.lower()] for m in by_item_mobs.get(name.lower(), []) for i, _r in uth[m]['items']
                if i.lower() in priced and priced[i.lower()] > 0]
        sell = int(statistics.median(vals)) if vals else 50
        trash(slug(name), name, sell * 2, 'no page: median sell value of the same monsters\' priced loot')
    OUT_ROWS.write_text(json.dumps(rows, indent=1), encoding='utf-8')
    OUT_REPORT.write_text(json.dumps(report, indent=1), encoding='utf-8')
    print(len(rows), 'items:', dict(Counter(v['kind'] for v in report.values())))


if __name__ == '__main__':
    main()
