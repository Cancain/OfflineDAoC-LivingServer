"""Merchant stock for a zone's merchants (ZONE CONTENT PROCESS.md step 7), from the old OfflineDAoC database (read
only): Mob.ItemsListTemplateID -> MerchantItem (page, slot, item template) -> ItemTemplate.
The period-data catalog notes these lists are the server's modern data, not proven 1.65 (no period vendor lists
survive) - kept, marked unverified in the zone ledger. Entries whose template doesn't exist are listed and left out.

    python build_merchants.py --zone=200
Writes godot/content/items/merchants.json: {lists: {list id: [[page, slot, item id], ...]}, items: {id: item},
missing: [...]}. Items use build_items' fields + the client icon number (objects.csv model -> icon)."""
import json, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT
from build_zone import zone_section
from build_items import FIELDS, object_icons, global_icon, DB

OUT = ROOT / 'godot/content/items/merchants.json'


def main():
    zone = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--zone=')), 200))
    sec = dict(line.split('=', 1) for line in zone_section(zone).splitlines() if '=' in line)
    x0, y0 = int(sec['region_offset_x']) * 8192, int(sec['region_offset_y']) * 8192
    x1, y1 = x0 + int(sec['width']) * 8192, y0 + int(sec['height']) * 8192
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    out = json.loads(OUT.read_text()) if OUT.exists() else {'lists': {}, 'items': {}, 'missing': []}
    icons = object_icons()
    cols = ', '.join(FIELDS)
    lists = {r[0] for r in db.execute(
        "select ItemsListTemplateID from Mob where Region=? and X>=? and X<? and Y>=? and Y<? and "
        "ItemsListTemplateID is not null and ItemsListTemplateID != ''", (int(sec['region']), x0, x1, y0, y1))}
    missing = set(out.get('missing', []))
    for lid in sorted(lists):
        entries = []
        for page, slot, tid in db.execute('select PageNumber, SlotPosition, ItemTemplateID from MerchantItem '
                                          'where ItemListID=? order by PageNumber, SlotPosition', (lid,)):
            if tid not in out['items'] or set(f.lower() for f in FIELDS) - set(out['items'][tid]):   # new fields
                row = db.execute(f'select Id_nb, {cols} from ItemTemplate where Id_nb=?', (tid,)).fetchone()
                if row is None:
                    missing.add(tid)
                    continue
                it = dict(zip(['id'] + [f.lower() for f in FIELDS], row))
                it['icon'] = global_icon(icons.get(int(it['model']), -1))
                out['items'][tid] = it
            entries.append([page, slot, tid])
        out['lists'][lid] = entries
    out['missing'] = sorted(missing)
    out['source'] = 'old OfflineDAoC DB MerchantItem / ItemTemplate (server lists, not proven 1.65)'
    OUT.write_text(json.dumps(out, indent=1), encoding='utf-8')
    print(len(lists), 'lists,', len(out['items']), 'items,', len(missing), 'missing templates')


if __name__ == '__main__':
    main()
