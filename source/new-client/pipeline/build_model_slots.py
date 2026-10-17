"""Where an item model is worn (owner 2026-10-15: "It's impossible for me to equip gear on 0.36c" - the server's item
packets (WriteItemData) carry no Item_Type, so the paper doll knew no slot for any item and refused every drop).
The shared server's own items (ItemTemplate + ItemUnique, read only) give each model's slot: the most common
Item_Type among the items using it (a few models serve two - 1884 is a belt and a bracer, 101 a necklace and the
mythical's - the drop on a slot itself still decides those; the server checks every move).
Writes godot/content/items/model_slots.json {model: item_type}.

    python pipeline/build_model_slots.py
"""
import json, sqlite3
from collections import Counter, defaultdict
from assets_pipeline import ROOT

DB = ROOT.parent / 'new class test - CLAUDE VERSION/runtime/data/opendaoc.sqlite3.db'
OUT = ROOT / 'godot/content/items/model_slots.json'
EQUIP = {10, 11, 12, 13, 21, 22, 23, 24, 25, 26, 27, 28, 29, 32, 33, 34, 35, 36, 37}


def main():
    con = sqlite3.connect(DB.as_uri() + '?mode=ro', uri=True)
    seen = defaultdict(Counter)
    for table in ('ItemTemplate', 'ItemUnique'):
        for model, it, n in con.execute(f'select Model, Item_Type, count(*) from {table} where Model > 0 group by Model, Item_Type'):
            if int(it) in EQUIP:
                seen[int(model)][int(it)] += int(n)
    out = {str(m): c.most_common(1)[0][0] for m, c in seen.items()}
    OUT.write_text(json.dumps(out, separators=(',', ':')), encoding='utf-8')
    print(len(out), 'models ->', OUT)


if __name__ == '__main__':
    main()
