"""Quest reward items with no old-DB template (owner 2026-10-10: "no quest reward should be missing").
Sources, in this order (owner 2026-10-10):
  1. period:  Allakhazam item pages as the Internet Archive captured them (2002-2004) - the item as it was then;
  2. Uthgard: the Uthgard bestiary's item pages (disorder.dk, a 1.65-era server; drops only, so few rewards);
  3. today's Allakhazam, "as long as the stats seem reasonable for the quest": post-1.65 bonus kinds dropped, the
     total held to the strongest period reward of that level (sanitize_live);
  4. no page anywhere: stats made up to fit the item and its quest (invent; listed in 1.65 EXCEPTIONS MADE.txt).
Every page gives slot, armour / weapon type, AF / absorb or DPS / speed / damage type, shield size, bonuses, focus,
charges, quality, weight, bonus level and levels. No page records the 3D appearance, so that is borrowed (owner: pick
one automatically): the model of an existing item of the same slot and type, the same realm first, nearest in level.
A charge / proc's spell is the existing spell of the same function and damage type nearest in strength.

    python build_reward_items.py      -> pipeline/data/reward_item_rows.json + reward_items_report.json
(build_quests.py reads them; then rebuild the quests: build_quests.py --zone=N for the zones.)"""
import json, re, sqlite3
from collections import defaultdict
from pathlib import Path
from assets_pipeline import ROOT

HERE = Path(__file__).resolve().parent
INDEX = HERE / 'data/period_index.sqlite'
OLD = ROOT / 'external/old_project'
DB = OLD / 'runtime/data/opendaoc.sqlite3.db'
NEED = OLD / 'development-source/research/period-data/quests/reward_items_needed.json'
QUESTS = ROOT / 'godot/content/quests/quests.json'
CLASSES = ROOT / 'godot/content/classes/classes.json'
_cls = json.loads(CLASSES.read_text(encoding='utf-8'))
_cls = _cls.get('classes', _cls)
CLASS_IDS = {({'albion': 1, 'midgard': 2, 'hibernia': 3}.get(c.get('realm', ''), 0), c['name'].lower()): c['id']
             for c in _cls.values() if isinstance(c, dict) and 'name' in c}
CLASS_INFO = {}                                        # class id -> stats, mana stat, skill / focus property ids
for _c in _cls.values():
    if not isinstance(_c, dict) or 'specs' not in _c:
        continue
    import ast as _ast
    _sp = _c['specs'] if isinstance(_c['specs'], list) else _ast.literal_eval(_c['specs'])
    _names = [x['spec'].lower() for x in _sp if x['level'] > -100]
    CLASS_INFO[int(_c['id'])] = {'name': _c['name'], 'stats': [_c.get('primary'), _c.get('secondary'), _c.get('tertiary')],
                                 'mana': _c.get('mana_stat') not in (None, '', 'None'), 'specs': _names}
OUT_ROWS = HERE / 'data/reward_item_rows.json'
OUT_REPORT = HERE / 'data/reward_items_report.json'

REALM = {'albion': 1, 'midgard': 2, 'hibernia': 3, 'all': 0}
SLOT = {'right hand': 10, 'left hand': 11, 'two hand': 12, 'two handed': 12, '2hand': 12, 'ranged': 13, 'helm': 21,
        'head': 21, 'hands': 22, 'feet': 23, 'jewel': 24, 'jewelry': 24, 'torso': 25, 'chest': 25, 'back': 26, 'cloak': 26,
        'legs': 27, 'arms': 28, 'neck': 29, 'waist': 32, 'wrist': 33, 'ring': 35, 'inventory': 40, 'mythical': 37,
        'righthand': 10, 'lefthand': 11}
WEAPON = {'crush': 2, 'slash': 3, 'thrust': 4, 'two handed': 6, 'polearm': 7, 'staff': 8, 'longbow': 9, 'long bow': 9,
          'crossbow': 10, 'flexible': 24, 'sword': 11, 'hammer': 12, 'axe': 13, 'spear': 14, 'composite bow': 15,
          'thrown': 16, 'left axe': 17, 'hand to hand': 25, 'recurve bow': 18, 'recurved bow': 18, 'blades': 19,
          'blunt': 20, 'piercing': 21, 'large weapon': 22, 'large weapons': 22, 'celtic spear': 23, 'scythe': 26,
          'shield': 42, 'instrument': 45, 'short bow': 5, 'shortbow': 5, 'bow': 5, 'shortbows': 5}
ARMOR = {'cloth': 32, 'leather': 33, 'studded': 34, 'chain': 35, 'plate': 36, 'reinforced': 37, 'scale': 38}
DAMAGE = {'crush': 1, 'slash': 2, 'thrust': 3, 'body': 10, 'cold': 11, 'energy': 12, 'heat': 13, 'matter': 14, 'spirit': 15}
STATS = {'strength': 1, 'dexterity': 2, 'constitution': 3, 'quickness': 4, 'intelligence': 5, 'piety': 6, 'empathy': 7,
         'charisma': 8, 'power': 9, 'hits': 10, 'body resist': 11, 'cold resist': 12, 'crush resist': 13,
         'energy resist': 14, 'heat resist': 15, 'matter resist': 16, 'slash resist': 17, 'spirit resist': 18,
         'thrust resist': 19, 'body': 11, 'cold': 12, 'energy': 14, 'heat': 15, 'matter': 16, 'spirit': 18,
         'acuity': 156, 'all primary melee skills': 164, 'all melee weapon skills': 164, 'all magic skills': 163,
         'all dual wielding skills': 167, 'all archery skills': 168, 'all focus levels': 165, 'armor factor': 148,
         'af': 148, 'power pool': 196}
SKILLS = {'two handed': 20, 'body destruction': 21, 'body magic': 21, 'chants': 22, 'critical strike': 23,
          'crossbow': 24, 'crush': 25, 'death servant': 26, 'deathsight': 27, 'dual wield': 28, 'earth magic': 29,
          'enhancement': 30, 'envenom': 31, 'fire magic': 32, 'flexible': 33, 'cold magic': 34, 'instruments': 35,
          'longbow': 36, 'long bow': 36, 'matter magic': 37, 'mind magic': 38, 'mind twisting': 38, 'painworking': 39,
          'parry': 40, 'polearm': 41, 'rejuvenation': 42, 'shield': 43, 'slash': 44, 'smite': 45, 'soulrending': 46,
          'spirit magic': 47, 'staff': 48, 'stealth': 49, 'thrust': 50, 'wind magic': 51, 'sword': 52, 'hammer': 53,
          'axe': 54, 'left axe': 55, 'spear': 56, 'mending': 57, 'augmentation': 58, 'darkness': 60,
          'suppression': 61, 'runecarving': 62, 'stormcalling': 63, 'beastcraft': 64, 'light': 65, 'void': 66,
          'mana': 67, 'composite bow': 68, 'battlesongs': 69, 'enchantment': 70, 'enchantments': 70, 'blades': 72,
          'blunt': 73, 'piercing': 74, 'large weapon': 75, 'large weapons': 75, 'mentalism': 76, 'regrowth': 77,
          'nurture': 78, 'nature': 79, 'music': 80, 'bard music': 80, 'celtic dual': 81, 'celtic spear': 82,
          'recurve bow': 83, 'valor': 84, 'subterranean': 85, 'bone army': 86, 'verdant path': 87,
          'creeping path': 88, 'arboreal path': 89, 'scythe': 90, 'thrown weapons': 91, 'hand to hand': 92,
          'short bow': 93, 'pacification': 94, 'savagery': 95, 'nightshade magic': 96, 'pathfinding': 97,
          'summoning': 98, 'cursing': 106, 'hexing': 107, 'witchcraft': 108, "odin's will": 105, 'path of fire': 32,
          'path of earth': 29, 'path of ice': 34, 'path of air': 51, 'calefaction': 32}
FOCUS = {'darkness': 120, 'suppression': 121, 'runecarving': 122, 'spirit': 123, 'fire': 124, 'air': 125, 'wind': 125,
         'cold': 126, 'ice': 126, 'earth': 127, 'light': 128, 'body': 129, 'matter': 130, 'mind': 132, 'void': 133,
         'mana': 134, 'enchantments': 135, 'mentalism': 136, 'summoning': 137, 'bone army': 138, 'painworking': 139,
         'deathsight': 140, 'death servant': 141, 'verdant path': 142, 'creeping path': 143, 'arboreal path': 144,
         'all': 165}
SPELL_TYPE = {'direct damage': 'DirectDamage', 'damage over time': 'DamageOverTime', 'heal': 'Heal',
              'lifedrain': 'Lifedrain', 'life drain': 'Lifedrain', 'damage shield': 'DamageShield',
              'damage add': 'DamageAdd', 'snare': 'SpeedDecrease', 'speed decrease': 'SpeedDecrease',
              'strength buff': 'StrengthBuff', 'constitution buff': 'ConstitutionBuff', 'dexterity buff': 'DexterityBuff',
              'armor factor buff': 'BaseArmorFactorBuff', 'mesmerize': 'Mesmerize', 'stun': 'Stun',
              'disease': 'Disease', 'bolt': 'Bolt', 'str/con buff': 'StrengthConstitutionBuff',
              'dex/qui buff': 'DexterityQuicknessBuff', 'ablative armor': 'AblativeArmor',
              'power regen': 'PowerRegenBuff', 'health regen': 'HealthRegenBuff', 'haste': 'CombatSpeedBuff',
              'combat speed buff': 'CombatSpeedBuff', 'speed enhancement': 'SpeedEnhancement',
              'resist buff': 'BodySpiritEnergyBuff', 'power transfer': 'PowerRegenBuff'}
HEADERS = ['Realm:', 'Slot:', 'Required', 'Requires Skill:', 'Requires Class:', 'Weapon Skill:', 'Damage Type:', 'DPS:',
           'Delay:', 'Speed:', 'Armor Factor:', 'Armor Absorb:', 'Shield Size:', 'Magical Bonuses:', 'Focus Bonuses:',
           'Magical Ability:', 'Item Bonuses:', 'Armor Modifiers:', 'Damage Modifiers', 'Quality:', 'Condition:', 'Starting Condition:',
           'Starting Duration:', 'Default Bonus:', 'Weight:', 'Utility:', 'Bonus Level:', 'Level to Attain:',
           'Levels of Use:', 'Rarity:', 'Last Updated:', 'Magic Level:', 'Charges:', 'Max Charges:', 'Usable in',
           'This item can be attained', 'Found in:', 'Post Comment', 'Minor Item', 'Incomplete info']


def norm(s):
    return re.sub(r'[^a-z0-9]+', ' ', s.lower()).strip()


def name_variants(n):
    """Ways the same item is written: page names carry suffixes - "(Alb)", "(1h)", "(chain)", "(level 33)" - and the
    quest data writes "2H Sword" where the page says "Two-handed Sword"."""
    out = {norm(n)}
    base = n
    while re.search(r'\s*\([^)]*\)\s*$', base):
        base = re.sub(r'\s*\([^)]*\)\s*$', '', base)
        out.add(norm(base))
    for v in list(out):
        out.add(' '.join(w for w in v.split(' ') if w != '1h'))
        out.add(' '.join('two handed' if w == '2h' else w for w in v.split(' ')))
    return {v for v in out if v}


# --- the pages ------------------------------------------------------------------------------------------------------

def load_pages():
    """norm(name) -> [{kind: 'period' | 'uthgard' | 'live', url, date, text (the item block)}]"""
    db = sqlite3.connect(INDEX)
    out = defaultdict(list)
    for src, kind in (('wayback-allakhazam/items_direct.jsonl.gz', 'period'), ('allakhazam-live/item.jsonl.gz', 'live')):
        for url, date, text in db.execute('select url, date, text from pages where source=?', (src,)):
            m = re.search(r'([^\.\:]{3,80}?) Realm: (Albion|Midgard|Hibernia|All)\b', text)
            if not m:
                continue
            name = m.group(1).strip()
            name = re.sub(r'^[\d\s]+(?=[A-Za-z])', '', name).strip()      # the archive's ad timestamp ("34 2003 ")
            block = text[m.start(1):m.start(1) + 2500]
            for v in name_variants(name):
                out[v].append({'kind': kind, 'url': url, 'date': date, 'name': name, 'text': block})
    for url, text in db.execute("select url, text from pages where source='uthgard/raw_pages.jsonl.gz' and url like '%item.php%'"):
        m = re.search(r'Item Name Information Stats (.+?) \1\.', text)
        if not m:
            continue
        name = m.group(1).strip()
        block = text[m.start(1):m.start(1) + 1500]
        for v in name_variants(name):
            out[v].append({'kind': 'uthgard', 'url': url, 'date': '', 'name': name, 'text': block})
    return out


def field(t, key):
    """The value after 'key' up to the next known header."""
    i = t.find(key)
    if i < 0:
        return None
    rest = t[i + len(key):]
    end = len(rest)
    for h in HEADERS:
        j = rest.find(' ' + h)
        if 0 <= j < end:
            end = j
    return rest[:end].strip()


def num(v, default=0.0):
    m = re.search(r'-?\d+(?:\.\d+)?', str(v or ''))
    return float(m.group(0)) if m else default


def bonuses(t, uthgard):
    out, unknown = [], []
    mb = field(t, 'Magical Bonuses:') or field(t, 'Item Bonuses:') or ''
    parts = [p.strip() for p in (mb.split(' - ') if uthgard else re.split(r'(?:(?<=pts)|(?<=lvl)|(?<=lvls)|(?<=%))\s+', mb)) if p.strip()]
    for x in parts:
        x = x.lstrip('- ').strip()
        m = re.match(r"(.+?)\s*:\s*([+-]?\d+)\s*(pts|%|lvls?)?", x)
        if not m:
            continue
        name, val = re.sub(r'\s+', ' ', m.group(1).strip().lower()), int(m.group(2))
        prop = next((d.get(n) for n in (name, name.rstrip('s'), name.replace(' magic', ''), name.replace(' magic', '').rstrip('s'))
                     for d in (STATS, SKILLS) if d.get(n)), None)
        if prop:
            out.append((prop, val))
        else:
            unknown.append(x)
    fb = field(t, 'Focus Bonuses:') or ''
    for x in re.split(r'(?:(?<=lvls)|(?<=lvl)|(?<=pts))\s+', fb):
        m = re.match(r'(.+?)\s*:\s*([+-]?\d+)', x.strip())
        if m:
            prop = FOCUS.get(m.group(1).strip().lower().replace(' focus', ''))
            if prop:
                out.append((prop, int(m.group(2))))
            else:
                unknown.append(x)
    return out, unknown


def parse(page, need):
    """An ItemTemplate row from one page."""
    t = page['text']
    ut = page['kind'] == 'uthgard'
    if ut:
        slot_s = (re.search(r'\bSlot (\w+)', t) or [None, 'inventory'])[1].lower()
        itype_s = (re.search(r'Item type (.+?) Damage type', t) or [None, ''])[1].strip().lower()
        dmg_s = (re.search(r'Damage type (\w+)', t) or [None, ''])[1].lower()
        level = int(num((re.search(r'\bLevel (\d+)', t) or [None, '1'])[1], 1))
        realm = REALM.get(need.get('realm', '').lower(), 0)
        item_type = SLOT.get(slot_s, 40)
        dps_af = spd_abs = type_damage = hand = 0
        object_type = 41 if item_type in (24, 26, 29, 32, 33, 35, 37) else 0
        if itype_s in ARMOR:
            object_type = ARMOR[itype_s]
            dps_af = int(num((re.search(r'(\d+) Base Factor', t) or [None, '0'])[1]))
            spd_abs = int(num((re.search(r'(\d+)% Absorption', t) or [None, '0'])[1]))
        elif itype_s in WEAPON:
            object_type = WEAPON[itype_s]
            dps_af = int(round(num((re.search(r'([\d.]+) Base DPS', t) or [None, '0'])[1]) * 10))
            spd_abs = int(round(num((re.search(r'([\d.]+) (?:Weapon|Shield) Speed', t) or [None, '0'])[1]) * 10))
            type_damage = DAMAGE.get(dmg_s, 0)
        quality = int(num((re.search(r'(\d+)% Quality', t) or [None, '100'])[1], 100))
        weight = 0
        bonus_pct = 0
        bonus_level = 0
    else:
        realm = REALM.get((field(t, 'Realm:') or '').split()[0].lower() if field(t, 'Realm:') else '', REALM.get(need.get('realm', '').lower(), 0))
        slot_s = (field(t, 'Slot:') or 'Inventory').lower()
        item_type = next((v for k, v in SLOT.items() if slot_s.startswith(k)), 40)
        skill = (field(t, 'Requires Skill:') or field(t, 'Weapon Skill:') or '').lower()
        skill = re.sub(r'\s*\(.*$', '', skill).strip()
        object_type = 41 if item_type in (24, 26, 29, 32, 33, 35, 37) else 0
        dps_af = spd_abs = type_damage = hand = 0
        if skill.startswith('armor:'):
            object_type = ARMOR.get(skill.split(':', 1)[1].strip(), 31)
            dps_af = int(num(field(t, 'Armor Factor:')))
            spd_abs = int(num(field(t, 'Armor Absorb:')))
        elif skill in WEAPON or field(t, 'DPS:') or field(t, 'Shield Size:'):
            if field(t, 'Shield Size:') or skill == 'shield':
                object_type = 42
                type_damage = {'small': 1, 'medium': 2, 'large': 3}.get((field(t, 'Shield Size:') or '').split()[0].lower() if field(t, 'Shield Size:') else '', 1)
                m = re.search(r'([\d.]+) Base DPS', t)
                dps_af = int(round(float(m.group(1)) * 10)) if m else 0
                m = re.search(r'([\d.]+) Shield Speed', t)
                spd_abs = int(round(float(m.group(1)) * 10)) if m else 0
            else:
                object_type = WEAPON.get(skill, 0)
                dps_af = int(round(num(field(t, 'DPS:')) * 10))
                spd_abs = int(round(num(field(t, 'Delay:') or field(t, 'Speed:')) * 10))
                type_damage = DAMAGE.get((field(t, 'Damage Type:') or '').split()[0].lower() if field(t, 'Damage Type:') else '', 0)
        level = int(num(field(t, 'Level to Attain:')) or num((field(t, 'Levels of Use:') or '').split('-')[0]) or num(field(t, 'Magic Level:')) or 1)
        quality = int(num(field(t, 'Quality:'), 100))
        weight = int(round(num(field(t, 'Weight:')) * 10))
        bonus_pct = int(num(field(t, 'Default Bonus:')))
        bonus_level = int(num(field(t, 'Bonus Level:')))
    if item_type == 12 or object_type in (6, 7, 8, 9, 10, 15, 18, 22, 23, 26):
        hand = 1
    elif item_type == 11 or object_type == 17:
        hand = 2
    bon, unknown = bonuses(t, ut)
    row = dict(Id_nb=need['id'], Name=need['name'], Level=level, Durability=50000, MaxDurability=50000,
               Condition=50000, MaxCondition=50000, Quality=quality or 100, DPS_AF=dps_af, SPD_ABS=spd_abs, Hand=hand,
               Type_Damage=type_damage, Object_Type=object_type, Item_Type=item_type, Weight=weight, Bonus=bonus_pct,
               BonusLevel=bonus_level, Realm=realm, AllowedClasses='0', IsPickable=1, IsDropable=1, IsTradable=0,
               Price=0, MaxCount=1, PackSize=1, Color=0, Extension=0)
    for k, (prop, val) in enumerate(bon[:10], 1):
        row[f'Bonus{k}Type'], row[f'Bonus{k}'] = prop, val
    has_stats = bool(bon or dps_af or (item_type == 40))
    return row, unknown, has_stats


# --- what the page can't say ----------------------------------------------------------------------------------------

def borrowers(db):
    rows = list(db.execute('select Item_Type, Object_Type, Realm, Level, Model from ItemTemplate where Model > 0'))
    spells = list(db.execute('select SpellID, Name, Type, Damage, DamageType, Value from Spell'))

    def model(item_type, object_type, realm, level):
        best = None
        for it, ot, r, lv, m in rows:
            if it != item_type or ot != object_type:
                continue
            score = (0 if r == realm else 1 if r == 0 else 2, abs((lv or 0) - level))
            if best is None or score < best[0]:
                best = (score, m)
        if best is None:
            for it, ot, r, lv, m in rows:
                if it == item_type:
                    score = (0 if r == realm else 1, abs((lv or 0) - level))
                    if best is None or score < best[0]:
                        best = (score, m)
        return best[1] if best else 488

    def spell(t):
        a = field(t, 'Magical Ability:')
        if not a:
            return None, None
        fn = (re.search(r'Function: (.+?)(?: Value:| Damage:| Range:| Cast| Duration| Amount|$)', a) or [None, ''])[1].strip().lower()
        stype = SPELL_TYPE.get(fn)
        if not stype:
            return None, f"charge / proc '{fn}' has no server equivalent"
        strength = num((re.search(r'(?:Value|Damage|Amount): ([\d.]+)', a) or [None, '0'])[1])
        dtype = DAMAGE.get((re.search(r'Damage Type: (\w+)', a) or [None, ''])[1].lower(), -1)
        cands = [s for s in spells if s[2] == stype and (dtype < 0 or s[4] == dtype)] or [s for s in spells if s[2] == stype]
        if not cands:
            return None, f'no {stype} spell on the server'
        s = min(cands, key=lambda s: abs((s[3] or s[5] or 0) - strength))
        return s[0], f'{fn} {strength:g} -> spell {s[0]} {s[1]}'
    return model, spell


# --- owner rulings 2026-10-10 ---------------------------------------------------------------------------------------
# Today's Allakhazam is used when no period / Uthgard page exists, "as long as the stats seem reasonable for the
# quest": bonus kinds that came after 1.65 are dropped and the total is held to the strongest period item of that
# level (sanitize_live). Items with no page anywhere get stats made up to fit the item and its quest (invent) - listed
# in "1.65 EXCEPTIONS MADE.txt".

# the quest data's name for an item whose page is under a slightly different name
ALIASES = {
    'cq_alb_ring_of_the_sound_diminished': ['Ring of Sound Diminished'],
    'cq_hib_entwined_vine_vest': ['Entwined Vined Vest'],
    'cq_mid_avboyning_bracer': ['Avboyning Bracelet'],
    'cq_hib_wind_bracelet': ['Wind Formed Bracelet'],
    'cq_hib_improved_spinner_s_cloak': ["Spinner's Cloak (level 33)"],
    'cq_alb_traveler_s_leggings': ["Soft Leather Traveler's Leggings"],
}
# one quest-data item that stands for a reward made per class: each class gets its own (the pages' Requires Class)
VARIANT_PAGES = {
    'cq_hib_banba_s_cloak_for_class': ("Banba's Cloak", [f"Banba's Cloak for {c}" for c in (
        'Animists', 'Bards', 'Blademasters', 'Champions', 'Druids', 'Eldritchs', 'Enchanters', 'Heroes', 'Mentalists',
        'Nightshades', 'Rangers', 'Valewalkers', 'Wardens')]),
    'cq_alb_ley_infused_belt': ('Ley Infused Belt', ['Ley Infused Belt of Power', 'Ley Infused Belt of Suppression',
                                                     'Ley Infused Belt of Vigor', 'Ley Infused Belt of the Chaste']),
    'cq_mid_trustan_s_belt': ("Trustan's Belt", ["Trustan's Embroidered Belt", "Trustan's Hand Embossed Belt",
                                                 "Trustan's Handmade Belt", "Trustan's Handwoven Belt"]),
}
# per-class rewards with no page at all: made up, one per class (name, slot, per class: (name, object type, item type))
VARIANT_INVENT = {
    'cq_hib_animist_bard_blademaster_champion_druid_eldritch_enchant': ("Viraniel's Belt", 32, {
        c: (f"{c}'s Belt", 41, 32) for c in ('Animist', 'Bard', 'Blademaster', 'Champion', 'Druid', 'Eldritch',
                                            'Enchanter', 'Hero', 'Mentalist', 'Nightshade', 'Ranger', 'Valewalker',
                                            'Warden')}),
    'cq_mid_stoneheart_staff_axe_hammer_sword_hand_to_hand_1h_or_2h': ('Stoneheart Weapon', 10, {
        'Warrior': ('Stoneheart Greatsword', 11, 12), 'Thane': ('Stoneheart Hammer', 12, 10),
        'Skald': ('Stoneheart Great Axe', 13, 12), 'Berserker': ('Stoneheart Axe', 13, 10),
        'Savage': ('Stoneheart Claw', 25, 10), 'Hunter': ('Stoneheart Sword', 11, 10),
        'Shadowblade': ('Stoneheart Blade', 11, 10), 'Healer': ('Stoneheart Mace', 12, 10),
        'Shaman': ('Stoneheart Maul', 12, 10), 'Runemaster': ('Stoneheart Staff', 8, 12),
        'Spiritmaster': ('Stoneheart Staff', 8, 12), 'Bonedancer': ('Stoneheart Staff', 8, 12)}),
}
# single items with no page at all: (item type, object type or None = the quest's class armour, a stat the name
# promises or None, a sibling page to take the bonus kinds from or None, plain sell price for no-stat items)
INVENT = {
    'cq_alb_avalon_defender_s_boots': (23, None, None, None, 0),
    'cq_alb_realm_defender_boots': (23, None, None, None, 0),
    'cq_alb_boots_of_prestidigitation': (23, None, None, 'Gloves of Prestidigitation', 0),
    'cq_alb_sleeves_of_prestidigitation': (28, None, None, 'Gloves of Prestidigitation', 0),
    'cq_alb_magician_s_dextrous_gloves': (22, None, None, "Magician's Dextrous Boots", 0),
    'cq_alb_magician_s_dextrous_sleeves': (28, None, None, "Magician's Dextrous Boots", 0),
    'cq_alb_magician_s_mysterious_gloves': (22, None, None, "Magician's Mysterious Boots", 0),
    'cq_alb_magician_s_mysterious_sleeves': (28, None, None, "Magician's Mysterious Boots", 0),
    'cq_alb_magician_s_sly_gloves': (22, None, None, "Magician's Sly Boots", 0),
    'cq_alb_mithran_boots_of_leo': (23, None, None, 'Mithran Sleeves of Perses', 0),
    'cq_alb_gurz': (10, 2, None, None, 0),                               # a gurz is a mace: crush
    'cq_alb_kiss_of_death': (10, 4, None, None, 0),                      # a mercenary's dagger: thrust
    'cq_alb_snowbinder_s_mantle': (26, 41, None, None, 0),
    'cq_alb_gold_nugget': (40, 0, None, None, 5000),                     # a sellable nugget, no stats
    'cq_alb_light_green_dye': (40, 0, None, None, 0),
    'cq_hib_belt_of_nimbleness': (32, 41, 2, None, 0),                   # nimbleness: dexterity
    'cq_hib_charming_necklace': (29, 41, 8, None, 0),                    # charming: charisma
    'cq_hib_choker_of_empathetic_properties': (29, 41, 7, None, 0),      # empathy
    'cq_hib_devastation': (12, 22, None, None, 0),                       # a large weapon
    'cq_hib_vine_entwined_hauberk': (25, None, None, 'Entwined Vined Vest', 0),
    'cq_hib_pot_of_enamel': (40, 0, None, None, 150000),                 # period: "sell for 15g"
    'cq_hib_ring_of_the_wolf': (35, 41, None, None, 0),
    'cq_hib_shadowblade': (10, 19, None, None, 0),                       # blades
    'cq_mid_brack_s_hammer': (10, 12, None, None, 0),
    'cq_mid_griffin_pelt_shield': (11, 42, None, None, 0),
    'cq_mid_hunter_s_mane': (21, None, None, None, 0),                   # a mane worn as a helm
    'cq_mid_njessi_staff_of_pure_thought': (12, 8, 5, None, 0),          # pure thought: intelligence
    'cq_mid_sleeves_of_buril': (28, None, None, None, 0),
}
CLASS_ARMOR = {'armsman': 36, 'paladin': 36, 'mercenary': 35, 'reaver': 35, 'cleric': 35, 'minstrel': 35,
               'scout': 34, 'friar': 33, 'infiltrator': 33, 'warrior': 35, 'thane': 35, 'skald': 35, 'healer': 35,
               'shaman': 35, 'berserker': 34, 'savage': 34, 'hunter': 34, 'shadowblade': 33, 'hero': 38,
               'champion': 38, 'warden': 38, 'druid': 38, 'blademaster': 37, 'ranger': 37, 'bard': 37,
               'nightshade': 33}
ABSORB = {32: 0, 33: 10, 34: 19, 37: 19, 35: 27, 38: 27, 36: 34}
POST_165 = {148, 156, 163, 164, 165, 167, 168, 196, 105, 106, 107}   # AF / acuity / "all" skills / power pool /
                                                                  # Catacombs-class skills: not in 1.65
SPEED = {8: 45, 22: 43, 25: 33, 42: 30}                              # default weapon speeds (x10) where no sibling


STAT_IDS = {'STR': 1, 'DEX': 2, 'CON': 3, 'QUI': 4, 'INT': 5, 'PIE': 6, 'EMP': 7, 'CHA': 8}
OBJ_SKILL = {2: 25, 3: 44, 4: 50, 6: 20, 7: 41, 8: 48, 11: 52, 12: 53, 13: 54, 17: 55, 14: 56, 25: 92, 19: 72, 20: 73,
             21: 74, 22: 75, 23: 82, 26: 90, 24: 33}


def class_props(cid):
    """The skill and focus property ids a class can use."""
    info = CLASS_INFO.get(cid, {})
    skills, focus = set(), set()
    for sp in info.get('specs', []):
        for n in (sp, sp.rstrip('s'), sp.replace(' magic', '')):
            if n in SKILLS:
                skills.add(SKILLS[n])
            if n.replace(' magic', '') in FOCUS:
                focus.add(FOCUS[n.replace(' magic', '')])
    return skills, focus


def fit(bon, cid):
    """How well bonuses suit a class: its stats, power for a caster, its own skills / focus; others count against."""
    info = CLASS_INFO.get(cid)
    if not info:
        return 0
    skills, focus = class_props(cid)
    want = [STAT_IDS.get(str(x).upper()) for x in info['stats']]
    sc = 0.0
    for t, v in bon:
        if t <= 8:
            sc += v * (2 if t == want[0] else 1.5 if t == want[1] else 1 if t in (want[2], 3) else -0.5)
        elif t == 9:
            sc += v * (2 if info['mana'] else -1)
        elif t == 10:
            sc += v * 0.25
        elif 11 <= t <= 19:
            sc += v
        elif 120 <= t <= 145:
            sc += 1 if t in focus else -2
        else:
            sc += v * (5 if t in skills else -3)
    return sc


def fit_to_classes(bon, classes, object_type):
    """Made-up items only: the weapon skill becomes the item's own; skills and focus lines no class of the quest
    has are swapped for the class's own (focus) or dropped."""
    if not classes:                                     # open to every class: no class's own skills
        return [b for b in bon if not 20 <= b[0] <= 110] or bon
    skills, focus = set(), set()
    for c in classes:
        a, b = class_props(c)
        skills |= a
        focus |= b
    out = []
    own = OBJ_SKILL.get(object_type)
    for t, v in bon:
        if t in OBJ_SKILL.values() and own and own in skills:
            t = own
        if 120 <= t <= 145 and t not in focus:
            spare = [f for f in sorted(focus) if f not in [x for x, _ in out]]
            if not spare:
                continue
            t = spare[0]
        if 20 <= t <= 110 and t not in skills:
            continue
        if t not in [x for x, _ in out]:
            out.append((t, v))
    return out


def utility(row):
    u = 0.0
    for k in range(1, 11):
        t, v = row.get(f'Bonus{k}Type'), row.get(f'Bonus{k}', 0)
        if not t or 120 <= t <= 145:                                    # focus levels are their own thing
            continue
        u += v * (1 if t <= 8 else 2 if t == 9 else 0.25 if t == 10 else 2 if 11 <= t <= 19 else 5)
    return u


def ceiling(period_rows, level):
    """The strongest period quest reward within 3 levels (90th percentile, focus left out)."""
    us = sorted(utility(r) for r in period_rows if abs(r['Level'] - level) <= 3)
    return us[int(len(us) * 0.9)] if us else None


def bonus_list(row):
    return [(row[f'Bonus{k}Type'], row[f'Bonus{k}']) for k in range(1, 11) if row.get(f'Bonus{k}Type')]


def set_bonuses(row, bon):
    for k in range(1, 11):
        row.pop(f'Bonus{k}Type', None)
        row.pop(f'Bonus{k}', None)
    for k, (t, v) in enumerate(bon[:10], 1):
        row[f'Bonus{k}Type'], row[f'Bonus{k}'] = t, v


def sanitize_live(row, period_rows, notes):
    bon = [(9, v) if t == 196 else (t, v) for t, v in bonus_list(row)]
    if len(bon) != len([1 for t, _ in bon if t != 196]) or any(t == 196 for t, _ in bonus_list(row)):
        notes.append('power pool % (patch 1.87 turned +power into it) back to +power')
    dropped = [b for b in bon if b[0] in POST_165]
    if dropped:
        bon = [b for b in bon if b[0] not in POST_165]
        notes.append(f'post-1.65 bonus kinds dropped: {dropped}')
    set_bonuses(row, bon)
    cap = ceiling(period_rows, row['Level'])
    u = utility(row)
    if cap and u > cap * 1.15:
        k = cap / u
        set_bonuses(row, [(t, max(1, int(round(v * k)))) if not 120 <= t <= 145 else (t, v) for t, v in bon])
        notes.append(f'bonuses scaled to {k:.2f}: utility {u:.0f} above the period level-{row["Level"]} ceiling {cap:.0f}')


def class_ids_of(row):
    return [int(c) for c in str(row.get('AllowedClasses', '0')).split(';') if c.strip().isdigit() and int(c) > 0]


def template_for(period_rows, item_type, realm, level, classes, sibling_rows=()):
    if sibling_rows:
        return min(sibling_rows, key=lambda r: abs(r['Level'] - level))
    pool = [r for r in period_rows if r['Item_Type'] == item_type and bonus_list(r)]
    def score(r):
        cl = class_ids_of(r)
        own = 0 if classes and cl and set(classes) & set(cl) else 1 if not cl else 2
        u = utility(r) + sum(1 for t, _ in bonus_list(r) if 120 <= t <= 145) or 1
        suit = max((fit(bonus_list(r), c) / u for c in classes), default=0) if classes else 0
        generic = sum(1 for t, _ in bonus_list(r) if t >= 20) if not classes else 0   # open to all: no skills
        return (own, -round(suit * 4), generic, 0 if r['Realm'] == realm else 1, abs(r['Level'] - level))
    return min(pool, key=score) if pool else None


def cap_of(t, level):
    """The most a made-up item gives of one bonus at its level (the period quest rewards' own range)."""
    if t <= 8:
        return max(1, round(level * 0.4))
    if t == 9:
        return max(1, level // 5)
    if t == 10:
        return max(4, level)
    if 11 <= t <= 19:
        return max(1, level // 5)
    if 120 <= t <= 145:
        return max(1, level)
    return max(1, level // 10 + 1)


def invent(iid, name, realm, level, classes, item_type, object_type, stat, sibling, price, period_rows, model,
           pages, cls_names):
    """Stats made up to fit the item and its quest (owner 2026-10-10): the bonus kinds of the nearest period quest
    reward of the same slot for the quest's classes (or a sibling item's page), scaled to the item's level; base AF /
    DPS from the 1.65 formulas."""
    notes = ['STATS MADE UP (no period, Uthgard or Allakhazam page)']
    if object_type is None:                                              # armour: the quest's class
        arm = [CLASS_ARMOR[cls_names[c]] for c in classes if cls_names.get(c) in CLASS_ARMOR]
        object_type = max(arm) if arm else 32
    sib = []
    if sibling:
        for v in name_variants(sibling):
            for p in pages.get(v, []):
                r, _, _ = parse(p, {'id': iid, 'name': sibling, 'realm': realm})
                sib.append(r)
        if sib and object_type in ABSORB and sib[0]['Object_Type'] in ABSORB:
            object_type = sib[0]['Object_Type']
    tpl = template_for(period_rows, item_type, REALM.get(realm.lower(), 0), level, classes, sib)
    row = dict(Id_nb=iid, Name=name, Level=level, Durability=50000, MaxDurability=50000, Condition=50000,
               MaxCondition=50000, Quality=100, DPS_AF=0, SPD_ABS=0, Hand=0, Type_Damage=0, Object_Type=object_type,
               Item_Type=item_type, Weight=10, Bonus=0, BonusLevel=0, Realm=REALM.get(realm.lower(), 0),
               AllowedClasses=';'.join(str(c) for c in classes) or '0', IsPickable=1, IsDropable=1, IsTradable=0,
               Price=price, MaxCount=1, PackSize=1, Color=0, Extension=0)
    if item_type == 40:
        notes.append('a plain item (no stats)' + (f', sells for {price} copper' if price else ''))
    else:
        if tpl:
            k = level / max(1, tpl['Level'])
            bon = [(t, min(cap_of(t, level), max(1, int(round(v * k))))) for t, v in bonus_list(tpl)]
            row.update(Quality=tpl['Quality'] or 100, Bonus=tpl['Bonus'], Weight=tpl['Weight'] or 10)
            notes.append(f"bonus kinds from {tpl['Name']} (level {tpl['Level']}), scaled to level {level}")
        else:
            bon = [(3, max(1, level // 3)), (10, max(1, level // 2))]
            notes.append('no template: constitution and hits by level')
        bon = fit_to_classes(bon, classes, object_type)
        if stat and stat not in [t for t, _ in bon]:
            stats = [i for i, (t, _) in enumerate(bon) if t <= 8]
            i = stats[0] if stats else 0
            bon.insert(i, (stat, bon.pop(i)[1] if bon else max(1, level // 3)))
            notes.append(f'stat {stat} from the name')
        set_bonuses(row, bon)
        cap = ceiling(period_rows, level)
        if cap and utility(row) > cap:
            k2 = cap / utility(row)
            set_bonuses(row, [(t, v if 120 <= t <= 145 else max(1, int(round(v * k2)))) for t, v in bon])
            notes.append(f'held to the period level-{level} ceiling ({cap:.0f})')
        us = sorted(utility(r) for r in period_rows if abs(r['Level'] - level) <= 3)
        mid = us[len(us) // 2] if us else 0
        if mid and 0 < utility(row) < mid * 0.8:                 # not weaker than a typical reward of its level
            k3 = mid / utility(row)
            set_bonuses(row, [(t, v if 120 <= t <= 145 else min(cap_of(t, level), max(1, int(round(v * k3)))))
                              for t, v in bonus_list(row)])
            notes.append(f'raised toward the period level-{level} median ({mid:.0f})')
        if object_type in ABSORB:                                        # 1.65 armour: AF = 2 x level (cloth 1 x)
            row.update(DPS_AF=level * (1 if object_type == 32 else 2), SPD_ABS=ABSORB[object_type])
        elif object_type == 42 or (object_type and object_type != 41 and item_type in (10, 11, 12, 13)):
            row['DPS_AF'] = int(round((1.2 + 0.3 * level) * 10))       # 1.65 weapon DPS by level
            row['SPD_ABS'] = (tpl['SPD_ABS'] if tpl and tpl['Object_Type'] == object_type and tpl['SPD_ABS']
                              else SPEED.get(object_type, 43 if item_type == 12 else 30))
            row['Type_Damage'] = (2 if object_type == 42 else {2: 1, 12: 1, 20: 1, 22: 1, 8: 1, 4: 3, 21: 3, 14: 3,
                                                                 25: 2}.get(object_type, 2))
            row['Hand'] = 1 if item_type == 12 else 2 if object_type == 17 else 0
            if object_type == 42:
                row.update(Type_Damage=2, Hand=0)                       # a medium shield
    row['Model'] = model(item_type, object_type, row['Realm'], level)
    notes.append(f"model {row['Model']} borrowed")
    return row, notes


def main():
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    quests = json.loads(QUESTS.read_text(encoding='utf-8'))
    old_need = json.loads(NEED.read_text(encoding='utf-8')).get('items', {}) if NEED.exists() else {}
    cls_names = {v: k[1] for k, v in CLASS_IDS.items()}
    cls_by_name = {k[1]: v for k, v in CLASS_IDS.items()}
    need = {}
    for q in quests['quests'].values():
        offered = {iid: '' for iid in q.get('final_rewards', []) + q.get('optional_rewards', [])}
        for st in q.get('steps', []):                     # "choose your reward" steps: the item named as offered
            for label, iid in ((st.get('custom') or {}).get('choices') or {}).items():
                offered[iid] = label
        for iid, label in offered.items():
            if db.execute('select 1 from ItemTemplate where Id_nb=?', (iid,)).fetchone():
                continue
            o = dict(old_need.get(iid, {}))
            if label and not o:
                o = {'name': re.sub(r'\s*\([^)]*\)\s*$', '', label).strip(), 'full': label}
            realm = o.get('realm') or {'alb': 'Albion', 'mid': 'Midgard', 'hib': 'Hibernia'}.get(iid[3:6], '')
            n = need.setdefault(iid, {'id': iid, 'name': o.get('name') or re.sub(r'^cq_(alb|mid|hib)_', '', iid).replace('_s_', "'s ").replace('_', ' ').title(),
                                      'full': o.get('full', ''), 'realm': realm, 'quests': [], 'qmin': 99, 'classes': set()})
            n['quests'].append(q['name'])
            n['qmin'] = min(n['qmin'], int(q.get('min', 1)))
            n['classes'] |= set(q.get('classes', [])) or {0}           # 0: an entry open to every class
    pages = load_pages()
    model, spell = borrowers(db)
    rows, report = [], {'built': {}, 'invented': {}, 'missing': {}, 'counts': defaultdict(int)}

    def from_pages(iid, n, names):
        realm_id = REALM.get(n['realm'].lower(), 0)
        cands = []
        for nm in names:
            for v in name_variants(nm):
                cands += pages.get(v, [])
        order = {'period': 0, 'uthgard': 1, 'live': 2}

        def realm_ok(p):
            if p['kind'] == 'uthgard':
                return 0
            r = REALM.get((field(p['text'], 'Realm:') or '').split()[0].lower() if field(p['text'], 'Realm:') else '', -1)
            return 0 if r in (realm_id, 0) else 1
        variant = (re.search(r'\(([^)]+)\)\s*$', n.get('full') or '') or [None, ''])[1].strip().lower()

        def variant_ok(p):                                 # "Skinner's Gloves (Leather)": the leather page first
            if not variant:
                return 0
            if variant in ARMOR:
                return 0 if re.search(r'Armor: ' + variant, p['text'], re.I) or re.search(r'Item type ' + variant, p['text'], re.I) else 1
            if variant in WEAPON:
                return 0 if re.search(r'(Weapon Skill|Item type):? ' + variant, p['text'], re.I) else 1
            return 0
        cands.sort(key=lambda p: (variant_ok(p), order[p['kind']], realm_ok(p), p['date']), reverse=False)
        built = None
        for p in cands:
            row, unknown, has_stats = parse(p, n)
            if has_stats or p is cands[-1]:
                built = (p, row, unknown, has_stats)
                break
        if built is None:
            return None
        p, row, unknown, has_stats = built
        notes = []
        if variant in ARMOR and row['Object_Type'] != ARMOR[variant] and row['Object_Type'] in ARMOR.values():
            row['Object_Type'] = ARMOR[variant]             # only another armour type's page exists
            notes.append(f'armour type {variant} from the name of the reward (the page is for another armour type)')
        words = norm(n['name']).split(' ')
        if '1h' in words and row['Item_Type'] == 12:        # the reward's own name says one-handed
            row.update(Item_Type=10, Hand=0)
            notes.append('one-handed from the name of the reward (the page says two-handed)')
        elif '2h' in words and row['Item_Type'] != 12:
            row.update(Item_Type=12, Hand=1)
            notes.append('two-handed from the name of the reward')
        rc = field(p['text'], 'Requires Class:') if p['kind'] != 'uthgard' else None
        if rc:
            ids = [str(CLASS_IDS[(row['Realm'], c.strip().lower())]) for c in re.split(r'\s*,\s*', rc)
                   if (row['Realm'], c.strip().lower()) in CLASS_IDS]
            if ids:
                row['AllowedClasses'] = ';'.join(ids)
        row['Model'] = model(row['Item_Type'], row['Object_Type'], row['Realm'], row['Level'])
        notes.append(f"model {row['Model']} borrowed (no page records the appearance)")
        sid, why = spell(p['text']) if p['kind'] != 'uthgard' else (None, None)
        if sid:
            charges = int(num(field(p['text'], 'Charges:')))
            if charges or row['Item_Type'] in (24, 26, 29, 32, 33, 35, 40) or row['Object_Type'] in (0, 41):
                row.update(SpellID=sid, Charges=charges or 10, MaxCharges=charges or 10)
            else:
                row.update(ProcSpellID=sid, ProcChance=0)
            notes.append(why)
        elif why:
            notes.append(why)
        if unknown:
            notes.append('bonuses with no server property: ' + '; '.join(unknown))
        if not has_stats:
            notes.append('the page has no stats (a plain item)')
        return p, row, notes

    # pass 1: every item with a page (period, Uthgard, then today's Allakhazam) - the period rows first, so the
    # Allakhazam ones can be held to them
    later = []
    for iid, n in sorted(need.items()):
        if iid in VARIANT_PAGES or iid in VARIANT_INVENT:
            later.append(iid)
            continue
        got = from_pages(iid, n, [n['name'], n['full'] or n['name']] + ALIASES.get(iid, []))
        if got is None:
            later.append(iid)
            continue
        p, row, notes = got
        if ALIASES.get(iid):
            row['Name'] = n['name']
            notes.append(f"page under the name {p['name']}")
        rows.append(row)
        report['built'][iid] = {'name': n['name'], 'quests': n['quests'], 'source': p['kind'], 'page': p['url'],
                                'date': p['date'], 'notes': notes}
        report['counts'][p['kind']] += 1
    period_rows = [r for r in rows if report['built'][r['Id_nb']]['source'] in ('period', 'uthgard')]
    for r in rows:
        b = report['built'][r['Id_nb']]
        if b['source'] == 'live':
            sanitize_live(r, period_rows, b['notes'])

    # pass 2: per-class rewards and items with no page
    for iid in later:
        n = need[iid]
        if iid in VARIANT_PAGES:
            label, names = VARIANT_PAGES[iid]
            variants, first, cands_v = {}, None, []
            for nm in names:
                sid = iid + '__' + re.sub(r'[^a-z0-9]+', '_', nm.lower()).strip('_')
                got = from_pages(sid, dict(n, id=sid, name=nm, full=''), [nm])
                if got is None:
                    continue
                p, row, notes = got
                row['Id_nb'] = sid
                if p['kind'] == 'live':
                    sanitize_live(row, period_rows, notes)
                rows.append(row)
                report['built'][sid] = {'name': nm, 'quests': n['quests'], 'source': p['kind'], 'page': p['url'],
                                        'date': p['date'], 'notes': notes}
                report['counts'][p['kind']] += 1
                for c in class_ids_of(row):
                    variants[str(c)] = sid
                first = first or row
                cands_v.append((sid, row))
            if not variants and cands_v:             # the pages name no class: by fit
                realm_id = REALM.get(n['realm'].lower(), 0)
                cl = sorted(n['classes'] - {0}) if 0 not in n['classes'] else [c for (r, _), c in CLASS_IDS.items() if r == realm_id]
                for c in cl:
                    if c in CLASS_INFO and not CLASS_INFO[c]['name'].lower() in ('fighter', 'acolyte', 'mage', 'elementalist', 'albionrogue', 'viking', 'mystic', 'seer', 'midgardrogue', 'guardian', 'magician', 'naturalist', 'stalker', 'forester'):
                        best = max(cands_v, key=lambda sr: fit(bonus_list(sr[1]), c))
                        variants[str(c)] = best[0]
                report['built'][iid + ' (classes by fit)'] = {'name': label, 'source': 'note', 'notes': ['pages name no class; each class gets the one whose bonuses suit it']}
            if first:
                rows.append(dict(first, Id_nb=iid, Name=label, AllowedClasses='0', variants=variants))
                report['built'][iid] = {'name': label, 'quests': n['quests'], 'source': 'per class',
                                        'notes': [f'gives the class\'s own: {variants}']}
                continue
        if iid in VARIANT_INVENT:
            label, slot, per = VARIANT_INVENT[iid]
            variants, first = {}, None
            for cname, (nm, ot, it) in per.items():
                cid = cls_by_name.get(cname.lower())
                if cid is None:
                    continue
                sid = iid + '__' + re.sub(r'[^a-z0-9]+', '_', nm.lower() + '_' + cname.lower()).strip('_')
                row, notes = invent(sid, nm, n['realm'], n['qmin'], [cid], it, ot, None, None, 0, period_rows, model,
                                    pages, cls_names)
                rows.append(row)
                report['invented'][sid] = {'name': nm, 'for': cname, 'quests': n['quests'], 'level': n['qmin'],
                                           'notes': notes}
                variants[str(cid)] = sid
                first = first or row
            rows.append(dict(first, Id_nb=iid, Name=label, AllowedClasses='0', variants=variants))
            report['built'][iid] = {'name': label, 'quests': n['quests'], 'source': 'per class (made up)',
                                    'notes': [f'gives the class\'s own: {variants}']}
            continue
        if iid in INVENT:
            it, ot, stat, sibling, price = INVENT[iid]
            row, notes = invent(iid, n['name'], n['realm'], n['qmin'], [] if 0 in n['classes'] else sorted(n['classes']), it, ot, stat, sibling,
                                price, period_rows, model, pages, cls_names)
            rows.append(row)
            report['invented'][iid] = {'name': n['name'], 'quests': n['quests'], 'level': n['qmin'], 'notes': notes}
            continue
        report['missing'][iid] = {k: (sorted(v) if isinstance(v, set) else v) for k, v in n.items()}
        report['counts']['missing'] += 1
    report['counts']['invented'] = len(report['invented'])
    OUT_ROWS.write_text(json.dumps(rows, indent=1), encoding='utf-8')
    report['counts'] = dict(report['counts'])
    OUT_REPORT.write_text(json.dumps(report, indent=1, default=lambda o: sorted(o) if isinstance(o, set) else str(o)),
                          encoding='utf-8')
    write_missing(report['missing'])
    print('reward items needed', len(need), 'rows', len(rows), report['counts'])


def write_missing(missing):
    """MISSING REWARD ITEMS.txt: anything still without stats (should be none)."""
    lines = ['QUEST REWARD ITEMS STILL WITHOUT STATS (pipeline/build_reward_items.py)', '',
             f'{len(missing)} items.', '']
    for iid, m in sorted(missing.items(), key=lambda kv: (kv[1].get('realm', ''), kv[1]['name'])):
        lines.append(f"{m['name']}  [{m.get('realm', '')}]  id {iid}   quests: {', '.join(m.get('quests', []))}")
    (ROOT / 'MISSING REWARD ITEMS.txt').write_text(chr(10).join(lines), encoding='utf-8')


if __name__ == '__main__':
    main()
