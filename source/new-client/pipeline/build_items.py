"""Items for the 1.65 in-game UI: the starting gear of every 1.65 base class and the client's icon sheets.

Data (read only): the old server's StarterEquipment + ItemTemplate tables. Class column = ';'-separated class ids;
only the 1.65 base classes (build_pregame.BASE_IDS) are kept. Later additions are left out: the Personal Bind Recall
Stone and Bead of Regeneration (rows with Class 0, OpenDAoC conveniences) and the Mauler gear (Catacombs class).
The Guardian rows name leaf_tacuil_* templates that are missing from the table; the same items exist as
leaf_tacuil_*3 (listed for the advanced Hibernian tanks), so those are used.
Owner 2026-10-09: in 1.65 a new character starts with ONLY a weapon - so 'starter' lists the class's weapon rows
(Object_Type < 32) - and its shield (42): owner 2026-10-10 "shields were part of kits" (patch 1.32 notes: "Midgard
Seers now start with a training shield"). No armour. The rest of the table's gear stays in 'items' as data.

Icons: objects.csv column 3 (the item's model row) holds the item's icon number. game.dll loads the icon sheets
SPL_0..400, CBT_500..800, WPN_900..1100, ITM_1200..1500, SKL_1600, WPN_1700, SPL_1800 (one 10x10 sheet of 32 px
icons per hundred). Item icon numbers are their own series and land on those sheets as follows (checked by eye
against the sheets, 2026-10-09):
    100-199 -> ITM_1200   (armour, jewels, misc; the old itm1_b sheet is the same picture)
    200-299 -> WPN_900    (weapons, shields, bows, arrows)
    500-599 -> ITM_1300   (vials, crafting bits, bags)
   2200-2299 -> ITM_1400  (house/siege objects; itm3_b)
Other series are later expansions and are not mapped (they show the question mark). Items carry the GLOBAL icon
number (sheet base + index), the same numbering the quickbar uses for spells and styles.

Writes godot/content/items/items.json and the sheets to godot/content/ui/icons/{original,x4plus} (UI art = x4plus
4x, one file at a time)."""
import csv, io, json, sys
from pathlib import Path
import sqlite3
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from build_pregame import BASE_IDS
import daoc_mpk

DB = ROOT / 'external/old_project/runtime/data/opendaoc.sqlite3.db'
OUT = ROOT / 'godot/content/items'
ICON_OUT = ROOT / 'godot/content/ui/icons'
SHEETS = {0: 'SPL_0', 100: 'SPL_100', 200: 'SPL_200', 300: 'SPL_300', 400: 'SPL_400', 500: 'CBT_500',
          600: 'CBT_600', 700: 'CBT_700', 800: 'CBT_800', 900: 'WPN_900', 1000: 'WPN_1000', 1100: 'WPN_1100',
          1200: 'ITM_1200', 1300: 'ITM_1300', 1400: 'ITM_1400', 1500: 'ITM_1500', 1600: 'SKL_1600',
          1700: 'WPN_1700', 1800: 'SPL_1800'}
ITEM_ICON_SERIES = {100: 1200, 200: 900, 500: 1300, 2200: 1400}
LATER = {'Personal_Bind_Recall_Stone', 'Bead_Of_Regeneration', 'plain_mauler_fistwrap', 'plainwood_mauler_staff'}
FIELDS = ['Name', 'Level', 'Durability', 'MaxDurability', 'Condition', 'MaxCondition', 'Quality', 'DPS_AF', 'SPD_ABS',
          'Hand', 'Type_Damage', 'Object_Type', 'Item_Type', 'Color', 'Weight', 'Model', 'Extension', 'Price',
          'Realm', 'IsDropable', 'IsTradable', 'MaxCount', 'PackSize', 'Bonus', 'AllowedClasses'] +          [f'Bonus{i}' for i in range(1, 11)] + [f'Bonus{i}Type' for i in range(1, 11)]
ENUMS = ROOT / 'external/old_project/development-source/server/GameServer/Enums'


def bonus_names():
    """Delve labels for item bonus types (the old server's eProperty numbering, read as data), worded like the period
    item pages that copy the in-game delve: 'Strength: 6 pts', 'Body Resist: 5%', 'Sword: +2 pts', 'Hits: 15 pts'."""
    import re
    out = {}
    for name, num in re.findall(r'^\s*(\w+)\s*=\s*(\d+),', (ENUMS / 'eProperty.cs').read_text(encoding='utf-8'), re.M):
        n = int(num)
        if name.endswith(('_First', '_Last')) or name == 'Undefined' or str(n) in out:
            continue
        words = lambda t: re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', t.replace('_', ' ')).title()
        if 1 <= n <= 8:
            out[str(n)] = [name, 'pts']
        elif name == 'MaxHealth':
            out[str(n)] = ['Hits', 'pts']
        elif name == 'MaxMana':
            out[str(n)] = ['Power', 'pts']
        elif name.startswith('Resist_'):
            out[str(n)] = [words(name[7:]) + ' Resist', '%']
        elif name.startswith('Skill_'):
            out[str(n)] = [words(name[6:]), '+pts']
        elif name.startswith('Focus_'):
            out[str(n)] = [words(name[6:]) + ' Focus', '+pts']
        else:
            out[str(n)] = [words(name), '']
    return out


def class_names():
    """Class id -> name for an item's AllowedClasses ("Usable by"), from the old server's eCharacterClass numbering."""
    import re
    text = (ENUMS / 'eCharacterClass.cs').read_text(encoding='utf-8')
    return {num: re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', name)
            for name, num in re.findall(r'^\s*(\w+)\s*=\s*(\d+),', text, re.M) if name != 'Unknown'}


def global_icon(n):
    for base, sheet in ITEM_ICON_SERIES.items():
        if base <= n < base + 100:
            return sheet + n - base
    return 0                                    # SPL_0 index 0 = the question mark


def object_icons():
    d = daoc_mpk.read_mpk(str(CLIENT / 'gamedata.mpk'))
    rows = list(csv.reader(io.StringIO(d['objects.csv'].decode('latin1'))))
    return {int(r[0]): int(r[3]) for r in rows[2:] if r and r[0].isdigit() and r[3].strip().isdigit()}


def main():
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    icons = object_icons()
    cols = ', '.join(FIELDS)
    items, starter = {}, {str(c): [] for c in BASE_IDS.values()}
    for cls, tid in db.execute('select Class, TemplateID from StarterEquipment order by StarterEquipmentID'):
        ids = {int(x) for x in str(cls).replace(' ', '').split(';') if x.strip().isdigit()}
        bases = [c for c in BASE_IDS.values() if c in ids]
        if not bases or tid in LATER:
            continue
        row = db.execute(f'select Id_nb, {cols} from ItemTemplate where Id_nb=?', (tid,)).fetchone()
        if row is None:
            row = db.execute(f'select Id_nb, {cols} from ItemTemplate where Id_nb=?', (tid + '3',)).fetchone()
        if row is None:
            print('missing template', tid)
            continue
        it = dict(zip(['id'] + [f.lower() for f in FIELDS], row))
        it['icon'] = global_icon(icons.get(int(it['model']), -1))
        items[it['id']] = it
        if not (0 < int(it['object_type']) < 32 or int(it['object_type']) == 42):   # weapons, and shields (42)
            continue
        for c in bases:
            if it['id'] not in starter[str(c)]:
                starter[str(c)].append(it['id'])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'bonus_names.json').write_text(json.dumps(bonus_names(), indent=1), encoding='utf-8')
    (OUT / 'class_names.json').write_text(json.dumps(class_names(), indent=1), encoding='utf-8')
    (OUT / 'items.json').write_text(json.dumps({'items': items, 'starter': starter,
                                                     'sheets': {str(k): v for k, v in SHEETS.items()}}, indent=1), encoding='utf-8')
    for c, lst in starter.items():
        print(c, len(lst), [items[i]['name'] for i in lst])

    src = ICON_OUT / 'original'
    src.mkdir(parents=True, exist_ok=True)
    icon_dir = CLIENT / 'icons'
    files = {p.stem.upper(): p for p in icon_dir.iterdir() if p.suffix.lower() == '.bmp'}
    for name in SHEETS.values():
        p = files.get(name.upper())
        if p is None:
            print('no sheet', name)
            continue
        q = src / f'{name}.png'
        if not q.exists() or q.stat().st_mtime < p.stat().st_mtime:
            Image.open(p).convert('RGB').save(q)
    from build_ui_classic import upscale_each
    upscale_each(src, ICON_OUT / 'x4plus')
    # icon border overlays (icons.csv borderId; spells / styles): brdr_0.bmp, 10 x 2 cells of 32 px, black = clear.
    # Thin coloured frames: a plain 4x Lanczos (the AI pass would invent texture in the black)
    import numpy as np
    b = files.get('BRDR_0')
    if b is not None:
        rgb = np.asarray(Image.open(b).convert('RGB'))
        alpha = np.where(rgb.max(axis=2) > 8, 255, 0).astype(np.uint8)
        im = Image.fromarray(np.dstack([rgb, alpha]), 'RGBA')
        im.save(ICON_OUT / 'original' / 'BRDR_0.png')
        im.resize((im.width * 4, im.height * 4), Image.LANCZOS).save(ICON_OUT / 'x4plus' / 'BRDR_0.png')


if __name__ == '__main__':
    main()
