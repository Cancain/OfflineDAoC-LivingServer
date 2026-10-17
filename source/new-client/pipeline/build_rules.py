"""Game rule NUMBERS for the MMOEngine's own combat / experience code (owner 2026-10-09: "you have my permission to
look at the server code from the previous project too just dont use any bot code"). Only data is read here - the
tables and constants in the old OfflineDAoC server source and its ServerProperty table - never code. The engine
implements the rules itself (game/combat/*.gd). Every value is listed with where it came from.

    python build_rules.py      -> godot/content/rules/rules.json"""
import json, re, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT

OLD = ROOT / 'external/old_project'
SRC = OLD / 'development-source/server/GameServer'
DB = OLD / 'runtime/data/opendaoc.sqlite3.db'
OUT = ROOT / 'godot/content/rules/rules.json'
BASE = ['Acolyte', 'AlbionRogue', 'Disciple', 'Elementalist', 'Fighter', 'Mage', 'Magician', 'Forester', 'Guardian',
        'Naturalist', 'Stalker', 'MidgardRogue', 'Mystic', 'Seer', 'Viking']   # ids from Enums/eCharacterClass.cs


def long_array(text, name):
    body = re.search(name + r'\s*=\s*\{(.*?)\};', text, re.S).group(1)
    body = re.sub(r'//[^\n]*', '', body)
    return [int(x) for x in re.findall(r'-?\d+', body)]


def armor_resists():
    out = {}
    # (realm, object type, slash, crush, thrust) exactly as WriteMeleeResists is called (Albion 1, Midgard 2, Hibernia 3;
    # Cloth 32, Leather 33, Studded 34, Chain 35, Plate 36, Reinforced 37, Scale 38)
    melee = [(1, 33, 0, -10, 10), (1, 36, 0, -10, 10), (1, 34, 0, 10, -10), (1, 35, 0, 10, -10),
             (3, 33, 10, -10, 0), (3, 37, 10, -10, 0), (3, 38, -10, 10, 0),
             (2, 34, -10, 0, 10), (2, 33, -10, 0, 10), (2, 35, 10, 0, -10)]
    for realm, ot, sl, cr, th in melee:
        out.setdefault(f'{realm}|{ot}', {}).update({'slash': sl, 'crush': cr, 'thrust': th})
    # (realm, object type, heat, cold, matter, energy) as WriteMagicResists is called
    magic = [(1, 33, -10, 10, -10, 0), (3, 33, -10, 10, -10, 0), (2, 33, -10, 10, -10, 0),
             (1, 34, 10, -10, -10, -10), (3, 37, 10, -10, -10, -10), (2, 34, 10, -10, -10, -10),
             (1, 35, 10, 0, 0, -10), (2, 35, 10, 0, 0, -10),
             (1, 36, 10, -10, 10, -10), (3, 38, 10, -10, 10, -10)]
    for realm, ot, he, co, ma, en in magic:
        out.setdefault(f'{realm}|{ot}', {}).update({'heat': he, 'cold': co, 'matter': ma, 'energy': en})
    return out


def db_ro():
    return sqlite3.connect(f'file:{DB}?mode=ro', uri=True)


def factions():
    out = {str(i): {'name': n, 'base': int(b or 0), 'friends': [int(i)], 'enemies': []}
           for i, n, b in db_ro().execute('select ID, Name, BaseAggroLevel from Faction')}
    for f, linked, friend in db_ro().execute('select FactionID, LinkedFactionID, IsFriend from LinkedFaction'):
        if str(f) in out and str(linked) in out:
            out[str(linked)]['friends' if friend else 'enemies'].append(int(f))
    return out


def main():
    player = (SRC / 'gameobjects/GamePlayer.cs').read_text(encoding='utf-8')
    living = (SRC / 'gameobjects/GameLiving.cs').read_text(encoding='utf-8')
    ids = dict(re.findall(r'^\s*(\w+)\s*=\s*(\d+),', (SRC / 'Enums/eCharacterClass.cs').read_text(encoding='utf-8'), re.M))
    classes = {}
    for name in BASE:
        cid = ids[name]
        p = SRC / f'playerclasses/base/Class{name}.cs'
        if not p.exists():
            continue
        t = p.read_text(encoding='utf-8')
        get = lambda k, d: int(re.search(k + r'\s*=\s*(\d+)', t).group(1)) if re.search(k + r'\s*=\s*(\d+)', t) else d
        classes[str(cid)] = {'name': name, 'base_hp': get('m_baseHP', 700), 'weapon_skill': get('m_wsbase', 400),
                             'weapon_skill_ranged': get('m_wsbaseRanged', 440)}
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    prop = lambda k: float(db.execute('select Value from ServerProperty where `Key`=?', (k,)).fetchone()[0])
    rules = {
        'source': 'old OfflineDAoC server source (tables / constants only) + its ServerProperty table',
        'xp_for_level': long_array(player, r'long\[\] XPForLevel')[:52],          # GamePlayer.XPForLevel
        'xp_for_living': long_array(living, r'long\[\] XPForLiving')[:52],        # GameLiving.XPForLiving (kill XP by level)
        'con_restore_cost': long_array(player, r'int\[\] prcRestore')[:52],       # GamePlayer.prcRestore: healer price per CON point
        'death': {'exp_loss_level': prop('pve_exp_loss_level'), 'con_loss_level': prop('pve_con_loss_level')},
        'xp_cap_percent': prop('xp_cap_percent'),                                 # solo kill XP cap: % of a same-level kill
        'max_camp_bonus': prop('max_camp_bonus'), 'max_dungeon_camp_bonus': prop('max_dungeon_camp_bonus'),
        'base_classes': classes,                                                   # playerclasses/base/Class*.cs
        'melee': {
            'base_miss_percent': 18,                 # AttackComponent.GetMissChance (pre-1.117C)
            'miss_per_level_pve': 4.0 / 3.0,         # 1.33% per level of difference (PvE)
            'quickness_speed': 0.002,                # speed * (1 - (QUI - 60) * 0.002), QUI capped at 250
            'slow_weapon_per_speed': 0.003,          # damage * (1 + (SPD_ABS - 20) * 0.003)
            'damage_cap_factor': 3.0,                # damage cap = 3 x base damage
            'npc_weapon_speed': {'one_hand': 3.0, 'two_hand': 4.0, 'ranged': 4.5},
            'npc_damage_f1': prop('pve_mob_damage_f1'), 'npc_damage_f2': prop('pve_mob_damage_f2'),
            'npc_weapon_skill_per_level': 2.5,       # GameNPC.GetWeaponSkill: L * 2.5 * (1 + (stat + 30) / 200)
            'npc_af': {'factor': 12.5, 'divisor': 200},   # ArmorFactorCalculator: (1 + L / 200) * L * 12.5
            'npc_absorb_per_level': 0.0054,          # GameLiving.GetBaseAbsorb: 27% at 50
            'player_extra_af_per_level': 0.4,        # CalculateTargetArmor
            'npc_variance': [0.9, 1.1],
            'pve_melee_damage': prop('pve_melee_damage'),
            'npc_style_chance': prop('gamenpc_chances_to_style'),   # NpcStyleComponent: positional / anytime styles
        },
        # GameNPC.SetStats with force_mob_autoset_stats on: STR / CON / DEX / QUI = base + (L - 1) x multiplier
        'npc_autoset': {'force': db.execute("select Value from ServerProperty where `Key`='force_mob_autoset_stats'").fetchone()[0] == 'True',
                        **{k: prop(f'mob_autoset_{k}') for k in ('str_base', 'str_multiplier', 'con_base', 'con_multiplier',
                                                                 'dex_base', 'dex_multiplier', 'qui_base', 'qui_multiplier')}},
        'npc_hp': {'per_level_plus_one': 11, 'per_level_squared': 0.6, 'con_offset': 25, 'per_con': 1.8},   # MaxHealthCalculator
        # SkillBase.InitializeRaceResists: the Race table (players' races and monsters' races alike), % by damage name
        'race_resists': {str(r[0]): dict(zip(('body', 'cold', 'crush', 'energy', 'heat', 'matter', 'natural', 'slash', 'spirit', 'thrust'), r[1:]))
                         for r in db.execute('select ID, ResistBody, ResistCold, ResistCrush, ResistEnergy, ResistHeat, ResistMatter, '
                                             'ResistNatural, ResistSlash, ResistSpirit, ResistThrust from Race')},
        # SkillBase.InitArmorResists: "realm|object type" -> damage name -> % (10 resistant / -10 vulnerable)
        'armor_resists': armor_resists(),
        'resist_cap': 70, 'resist_buff_cap': 24,           # ResistCalculator.HardCap / BuffBonusCap
        # FactionMgr.Init: the Faction table (BaseAggroLevel = a new character's hostility, -100..100; > 75 aggressive,
        # > 50 hostile, > 25 neutral, else friendly) and LinkedFaction (FactionID becomes a friend / enemy of
        # LinkedFactionID's faction); every faction is its own friend
        'factions': factions(),
        # BindPoint (GamePlayer.Bind / BindArea circles): [region, x, y, z, radius, realm] - realm 0 binds anyone
        # (NormalServerRules.IsAllowedToBind); one bind a minute (BindAllowInterval 60000)
        'bind_points': [list(r) for r in db_ro().execute('select Region, X, Y, Z, Radius, Realm from BindPoint')],
        'bind_interval_s': 60,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rules, indent=1), encoding='utf-8')
    print(len(rules['xp_for_level']), 'levels,', len(classes), 'base classes:', {k: (v['name'], v['base_hp'], v['weapon_skill']) for k, v in classes.items()})


if __name__ == '__main__':
    main()
