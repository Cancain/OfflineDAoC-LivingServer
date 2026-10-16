"""Classes, specializations, spell lines, spells, combat styles and abilities for the 1.65 classes - data only, from
the old OfflineDAoC server's class files (playerclasses/*.cs: numbers and names, read as text) and its database
(Specialization, ClassXSpecialization, SpecXAbility, SpellLine, LineXSpell, Spell, Style, StyleXSpell, Ability).
The engine implements the rules itself (game/classes, game/combat). Never bot code (owner rule).

1.65 classes only: the base classes and the advanced classes of Classic + Shrouded Isles (Necromancer / Disciple
are Shrouded Isles: Allakhazam had the Necromancer epic armour in January 2003, and the 1.65 client's creation screen
offers Disciple). Left out as later: Heretic, Valkyrie, Warlock, Bainshee, Vampiir, the Maulers (Catacombs and after)
and the old project's custom Sluaghbinder.

    python build_classes.py
Writes godot/content/classes/{classes,specs,spells,styles,abilities}.json."""
import json, re, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT

OLD = ROOT / 'external/old_project'
SRC = OLD / 'development-source/server/GameServer'
DB = OLD / 'runtime/data/opendaoc.sqlite3.db'
OUT = ROOT / 'godot/content/classes'

BASE = ['Fighter', 'AlbionRogue', 'Acolyte', 'Elementalist', 'Mage', 'Viking', 'MidgardRogue', 'Mystic', 'Seer',
        'Guardian', 'Stalker', 'Naturalist', 'Magician', 'Forester', 'Disciple']
ADVANCED = {
    'albion': ['Armsman', 'Cabalist', 'Cleric', 'Friar', 'Infiltrator', 'Mercenary', 'Minstrel', 'Necromancer', 'Paladin',
               'Reaver', 'Scout', 'Sorcerer', 'Theurgist', 'Wizard'],
    'midgard': ['Berserker', 'Bonedancer', 'Healer', 'Hunter', 'Runemaster', 'Savage', 'Shadowblade', 'Shaman', 'Skald',
                'Spiritmaster', 'Thane', 'Warrior'],
    'hibernia': ['Animist', 'Bard', 'Blademaster', 'Champion', 'Druid', 'Eldritch', 'Enchanter', 'Hero', 'Mentalist',
                 'Nightshade', 'Ranger', 'Valewalker', 'Warden'],
}
REALM_OF_BASE = {'Fighter': 'albion', 'AlbionRogue': 'albion', 'Acolyte': 'albion', 'Elementalist': 'albion',
                 'Mage': 'albion', 'Viking': 'midgard', 'MidgardRogue': 'midgard', 'Mystic': 'midgard',
                 'Seer': 'midgard', 'Guardian': 'hibernia', 'Stalker': 'hibernia', 'Naturalist': 'hibernia',
                 'Magician': 'hibernia', 'Forester': 'hibernia', 'Disciple': 'albion'}
SPECS = {}                                                  # Specs.Slash -> "Slash" (filled from GlobalConstants)
STATS = {'STR': 0, 'CON': 1, 'DEX': 2, 'QUI': 3, 'INT': 4, 'PIE': 5, 'EMP': 6, 'CHA': 7}



def style_trail(row):
    """styles.csv's trail columns for a style row (owner 2026-10-10: the style colour flash): afterimages of the
    weapon (Imagenum) shown for Duration ms after Buildup ms into the style swing, tinted Red / Green / Blue; Hit
    Effect a client effect on the hit (0 for nearly all). None when the row is missing."""
    if not row or len(row) < 11:
        return None
    n = lambda i: int(row[i]) if row[i].strip().lstrip('-').isdigit() else 0
    return {'images': n(4), 'ms': n(5), 'buildup': n(6), 'rgb': [n(7), n(8), n(9)], 'hit_effect': n(10)}

def class_file(name):
    for sub in ('base', 'albion', 'midgard', 'hibernia'):
        p = SRC / f'playerclasses/{sub}/Class{name}.cs'
        if p.exists():
            return p.read_text(encoding='utf-8')
    raise SystemExit(f'no class file for {name}')


def parse_class(name, ids, defaults):
    t = class_file(name)
    attr = re.search(r'\[CharacterClass\(\(int\)eCharacterClass\.(\w+),\s*"([^"]*)"(?:,\s*"([^"]*)")?(?:,\s*"([^"]*)")?\)\]', t)
    parent = re.search(r'class Class\w+\s*:\s*Class(\w+)', t)
    num = lambda k: int(re.search(k + r'\s*=\s*(\d+)', t).group(1)) if re.search(k + r'\s*=\s*(\d+)', t) else None
    stat = lambda k: (re.search(k + r'\s*=\s*eStat\.(\w+)', t).group(1) if re.search(k + r'\s*=\s*eStat\.(\w+)', t) else None)
    races = re.search(r'EligibleRaces\s*=>\s*new List<PlayerRace>\(\)\s*\{(.*?)\}', t, re.S)
    race_list = []
    if races:
        body = '\n'.join(l for l in races.group(1).splitlines() if not l.strip().startswith('//'))
        race_list = re.findall(r'PlayerRace\.(\w+)', body)
    prof = re.search(r'm_profession\s*=\s*"([^"]+)"', t)
    ctype = re.search(r'eClassType\.(\w+)', t)                # ListCaster / Hybrid / PureTank (inherited when not set)
    at = re.search(r'AutotrainableSkills\s*=\s*new\[\]\s*\{([^}]*)\}', t)
    autotrain = [SPECS.get(x, x) for x in re.findall(r'Specs\.(\w+)', at.group(1))] if at else None
    out = dict(defaults)
    out.update({k: v for k, v in {
        'spec_multiplier': num('m_specializationMultiplier'), 'base_hp': num('m_baseHP'),
        'weapon_skill': num('m_wsbase'), 'weapon_skill_ranged': num('m_wsbaseRanged'),
        'primary': stat('m_primaryStat'), 'secondary': stat('m_secondaryStat'), 'tertiary': stat('m_tertiaryStat'),
        'mana_stat': stat('m_manaStat'), 'profession': prof.group(1).split('.')[-1] if prof else None,
        'class_type': ctype.group(1) if ctype else None,
        'autotrain': autotrain}.items()
        if v is not None})
    out.update({'id': int(ids[name]), 'key': name, 'name': attr.group(2) if attr else name,
                'base': attr.group(3) if attr and attr.group(3) else None,
                'parent': parent.group(1) if parent else None,
                'left_hand': 'CanUseLefthandedWeapon' in t and re.search(r'CanUseLefthandedWeapon\s*\{\s*get\s*\{\s*return true', t) is not None,
                'races': race_list or defaults.get('races', [])})
    return out


def main():
    txt = (SRC / 'gameutils/SkillConstants.cs').read_text(encoding='utf-8', errors='ignore')
    body = txt.split('class Specs', 1)[1]
    SPECS.update(dict(re.findall(r'const string (\w+)\s*=\s*"([^"]+)"', body.split('class ', 1)[0])))
    ids = dict(re.findall(r'^\s*(\w+)\s*=\s*(\d+),', (SRC / 'Enums/eCharacterClass.cs').read_text(encoding='utf-8'), re.M))
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    classes = {}
    base_info = {}
    for b in BASE:
        c = parse_class(b, ids, {'spec_multiplier': 10, 'base_hp': 700, 'weapon_skill': 400, 'weapon_skill_ranged': 440})
        c.update({'realm': REALM_OF_BASE[b], 'advanced': [], 'is_base': True})
        classes[str(c['id'])] = c
        base_info[b] = c
    for realm, names in ADVANCED.items():
        for n in names:
            t = class_file(n)
            parent = re.search(r'class Class\w+\s*:\s*Class(\w+)', t).group(1)
            defaults = {k: base_info[parent][k] for k in ('spec_multiplier', 'base_hp', 'weapon_skill', 'weapon_skill_ranged',
                                                         'primary', 'secondary', 'tertiary', 'mana_stat', 'races', 'class_type')
                        if k in base_info.get(parent, {})}
            c = parse_class(n, ids, defaults)
            c.update({'realm': realm, 'is_base': False, 'base_class': base_info[parent]['id']})
            classes[str(c['id'])] = c
            base_info[parent]['advanced'].append(c['id'])
    keep = set(int(k) for k in classes)
    # specializations per class (LevelAcquired) and the abilities they grant
    cxs = {}
    for cid, key, lvl in db.execute('select ClassID, SpecKeyName, LevelAcquired from ClassXSpecialization'):
        if int(cid) in keep:
            cxs.setdefault(str(cid), []).append({'spec': key, 'level': int(lvl or 1)})
    for cid, lst in cxs.items():
        classes[cid]['specs'] = sorted(lst, key=lambda e: (e['level'], e['spec']))
    abilities_by_class = {}
    for spec, lvl, akey, alvl, cid in db.execute('select Spec, SpecLevel, AbilityKey, AbilityLevel, ClassId from SpecXAbility'):
        if int(cid or 0) in keep or int(cid or 0) == 0:
            abilities_by_class.setdefault(str(cid or 0), []).append({'spec': spec, 'spec_level': int(lvl), 'ability': akey,
                                                                     'level': int(alvl or 1)})
    used_specs = {e['spec'] for c in classes.values() for e in c.get('specs', [])}
    specs = {k: {'name': n, 'icon': int(i or 0), 'description': d or '', 'implementation': impl or ''}
             for k, n, i, d, impl in db.execute('select KeyName, Name, Icon, Description, Implementation from Specialization')
             if k in used_specs}
    # spell lines tied to those specs (+ base lines), their spells by level
    lines = {}
    for key, name, spec, base, hint in db.execute('select KeyName, Name, Spec, IsBaseLine, ClassIDHint from SpellLine'):
        if spec in used_specs and (not hint or int(hint) in keep):
            lines[key] = {'name': name, 'spec': spec, 'baseline': bool(base), 'class_hint': int(hint or 0), 'spells': []}
    spell_ids = set()
    for line, sid, lvl in db.execute('select LineName, SpellID, Level from LineXSpell'):
        if line in lines:
            lines[line]['spells'].append([int(sid), int(lvl)])
            spell_ids.add(int(sid))
    for l in lines.values():
        l['spells'].sort(key=lambda e: e[1])
    # styles per spec (the class's own or shared ClassId 0) and their proc spells
    styles = {}
    cols = ['StyleID', 'ID', 'ClassId', 'Name', 'SpecKeyName', 'SpecLevelRequirement', 'Icon', 'EnduranceCost',
            'StealthRequirement', 'OpeningRequirementType', 'OpeningRequirementValue', 'AttackResultRequirement',
            'WeaponTypeRequirement', 'GrowthOffset', 'GrowthRate', 'BonusToHit', 'BonusToDefense', 'TwoHandAnimation',
            'RandomProc', 'ArmorHitLocation']
    for r in db.execute(f'select {",".join(cols)} from Style'):
        s = dict(zip([c.lower() for c in cols], r))
        if s['speckeyname'] in used_specs and (int(s['classid'] or 0) in keep or int(s['classid'] or 0) == 0):
            styles[str(s['styleid'])] = s
    for sid, cid, style_id, chance in db.execute('select SpellID, ClassID, StyleID, Chance from StyleXSpell'):
        if str(style_id) in styles:
            styles[str(style_id)].setdefault('procs', []).append({'spell': int(sid), 'class': int(cid or 0), 'chance': int(chance or 0)})
            spell_ids.add(int(sid))
    # spells (and their sub-spells, followed)
    scols = [r[1] for r in db.execute('pragma table_info(Spell)')]
    spells, todo = {}, set(spell_ids)
    while todo:
        sid = todo.pop()
        r = db.execute('select * from Spell where SpellID=?', (sid,)).fetchone()
        if r is None:
            continue
        s = {k.lower(): v for k, v in zip(scols, r) if k not in ('LastTimeRowUpdated', 'Spell_ID', 'PackageID')}
        spells[str(sid)] = s
        sub = int(s.get('subspellid') or 0)
        if sub and str(sub) not in spells:
            todo.add(sub)
        # a proc buff's spell (BaseProcSpellHandler: SkillBase.GetSpellByID(Value))
        proc = int(s.get('value') or 0) if s.get('type') in ('OffensiveProc', 'DefensiveProc', 'OffensiveProcPvE') else 0
        if proc > 0 and str(proc) not in spells:
            todo.add(proc)
    abil = {k: {'name': n, 'icon': int(i or 0), 'description': d or '', 'implementation': impl or ''}
            for k, n, i, d, impl in db.execute('select KeyName, Name, IconID, Description, Implementation from Ability')}
    # icons the client's way: spells.csv (by client effect) / styles.csv (by style id) give an icons.csv id, which
    # gives the global sheet icon (SPL_0.. CBT_500..) and an optional border overlay (brdr_0.bmp)
    import csv, io
    from daoc_mpk import read_mpk
    from assets_pipeline import CLIENT
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    tab = lambda n: {r[0].strip(): r for r in csv.reader(io.StringIO(g[n].decode('latin1'))) if r and r[0].strip().isdigit()}
    icons, csp, cst = tab('icons.csv'), tab('spells.csv'), tab('styles.csv')

    def resolve(icon_id):
        r = icons.get(str(icon_id).strip())
        if not r:
            return [0, -1]
        return [int(r[2]) if r[2].strip().lstrip('-').isdigit() else 0, int(r[3]) if r[3].strip().lstrip('-').isdigit() else -1]
    for sid, sp in spells.items():
        row = csp.get(str(sp.get('clienteffect') or sp.get('icon') or 0))
        sp['icon_base'], sp['icon_border'] = resolve(row[2]) if row else [0, -1]
    for sid, st in styles.items():
        row = cst.get(str(st.get('icon') or 0))
        # the weapon's style trail (styles.csv Imagenum / Duration / Buildup / Red / Green / Blue / Hit Effect): see
        # style_trail
        st['icon_base'], st['icon_border'] = resolve(row[2]) if row else [0, -1]
        st['animation'] = int(row[3]) if row and row[3].strip().isdigit() else 0
        # with a two-handed weapon the server sends TwoHandAnimation instead of Icon (StyleProcessor.ExecuteStyle)
        row2 = cst.get(str(st.get('twohandanimation') or 0))
        st['animation_2h'] = int(row2[3]) if row2 and row2[3].strip().isdigit() else st['animation']
        st['trail'], st['trail_2h'] = style_trail(row), style_trail(row2 or row)
    # profession (guild) names in English: PlayerClass.Profession.PathofHarmony -> "Path of Harmony"
    langs = sorted((OLD / 'development-source/server').rglob('languages/EN/PlayerClasses.txt'))
    prof = {}
    if langs:
        for line in langs[0].read_text(encoding='utf-8', errors='ignore').splitlines():
            m = re.match(r'PlayerClass\.Profession\.(\w+):\s*(.+)', line.strip())
            if m:
                prof[m.group(1)] = m.group(2).strip()
    for c in classes.values():
        if c.get('profession'):
            c['profession'] = prof.get(c['profession'], c['profession'])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'classes.json').write_text(json.dumps({'classes': classes, 'abilities_by_class': abilities_by_class}, indent=1), encoding='utf-8')
    (OUT / 'specs.json').write_text(json.dumps({'specs': specs, 'lines': lines}, indent=1), encoding='utf-8')
    (OUT / 'spells.json').write_text(json.dumps(spells), encoding='utf-8')
    (OUT / 'styles.json').write_text(json.dumps(styles, indent=1), encoding='utf-8')
    (OUT / 'abilities.json').write_text(json.dumps(abil, indent=1), encoding='utf-8')
    print(len(classes), 'classes,', len(specs), 'specs,', len(lines), 'spell lines,', len(spells), 'spells,',
          len(styles), 'styles,', len(abil), 'abilities')
    for cid in ('52', '43', '48'):
        c = classes.get(cid, {})
        print(cid, c.get('name'), c.get('base'), c.get('spec_multiplier'), c.get('primary'), c.get('profession'),
              [e['spec'] + '@' + str(e['level']) for e in c.get('specs', [])])


if __name__ == '__main__':
    main()
