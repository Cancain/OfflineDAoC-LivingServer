"""A zone's people and monsters for the MMOEngine (ZONE CONTENT PROCESS.md step 9), from the old OfflineDAoC database
(read only; its Mob table is the vetted 1.65 spawn set - later mobs live in offline_classic165_removed_mobs).

    python build_npcs.py --zone=200
Writes godot/content/zones/zoneNNN/npcs.json:
  spawns: [{id, name, guild, level, realm, role, model (monsters.json key), size, gender, pos [x, y, z] metres in
            zone-local engine axes, heading (DAoC 0..4095), aggro_level, aggro_range, roam, flags, items, equipment,
            faction, body_type}]
  equipment: {template id: [{slot, model, color, effect, extension}]}
  con: the con-colour table (capnbry.net/daoc/concolors.html, carried by the old server's ConLevels.cs):
       con[player level][npc level] = -3 grey .. 3 purple
  examine: the examine-message wording (period chat logs quoted on Allakhazam: "You examine Rory. He is friendly.",
           "She is neutral towards you.", "He is aggressive towards you!", "...friendly and is a guard.")
Coordinates: DAoC zone-local units (global - zone offset) -> engine (x, height, y) x 0.025, like the zone fixtures."""
import json, re, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT
from build_zone import zone_section

DB = ROOT / 'external/old_project/runtime/data/opendaoc.sqlite3.db'
M = 0.025
# DOL class type -> the NPC's job (what clicking it does; the examine suffix)
ROLES = {'GameMerchant': 'merchant', 'GameGuard': 'guard', 'GameHealer': 'healer', 'Blacksmith': 'smith',
         'Enchanter': 'enchanter', 'GameHastener': 'hastener', 'GameStableMaster': 'stablemaster',
         'LiveTeleporter': 'teleporter', 'GameVaultKeeper': 'vaultkeeper'}
TRAINERS = {'ForesterTrainer': 'Forester', 'GuardianTrainer': 'Guardian', 'MagicianTrainer': 'Magician',
            'NaturalistTrainer': 'Naturalist', 'StalkerTrainer': 'Stalker'}
# NPC types the old server spawned that 1.65 didn't have (owner 2026-10-09): town teleporters (the "Channeler"
# LiveTeleporter by the Mag Mell bindstone) and hasteners (Filidh Morven) - left out of the zone
NOT_165 = {'LiveTeleporter', 'GameHastener',
           # the old project's own additions (Tir na Nog, 2026-10-09): account vaults (patch 1.89-era), the Realm
           # Exchange broker and treasury clerk (the old server's economy - the MMOEngine gets its own later), Atlas
           # bounty merchants / trainers, effect NPCs, the custom Sluaghbinder's trainer
           'AccountVaultKeeper', 'RealmExchangeBroker', 'RoyalTreasuryClerk', 'GameBountyMerchant', 'AtlasTrainer',
           'EffectNPC', 'SluaghbinderTrainer',
           # owner 2026-10-09: only 1.65-accurate NPCs - the Atlas-style Old Frontiers teleporters / assistants /
           # merchants, keep hasteners (~1.70), training dummies, the realm-point trade-in merchant, basic crafting
           'OFTeleporter', 'OFAssistant', 'InlandTeleporter', 'OFMerchant', 'OFMerchantHome', 'FrontierHastener',
           'DPSDummy', 'HitbackDummy', 'HealDummy', 'RPTradeInMerchant', 'BasicCraftingMaster',
           # the old project's NPC audit (period-data/bestiary/npc_audit.csv: CapnBry 2002-04 sightings, Illia's
           # bestiary, class origins): Atlas rechargers, Darkness Rising seals merchants, housing market explorers,
           # the old project's emissary teleporters, keep merchants, reskin / buff vendors, the "lord of bosses"
           'Recharger', 'GameEmeraldSealsMerchant', 'GameDiamondSealsMerchant', 'GameSapphireSealsMerchant',
           'MarketExplorer', 'SimpleTeleporter', 'GuardMerchant', 'ItemModel', 'BuffMerchant', 'LordOfBoss'}
# ...and custom NPCs on plain classes, by guild title / name / merchant list
NOT_165_GUILDS = {'exchange guard', 'consignment banker', 'reskin npc', 'reskin master', 'we will pamp you up',
                  'our strongest potions', 'tinctures and toxins', 'assistant to the recharger', 'first peri-peri',
                  'lord of bosses', 'bindstone clerk', 'recharger', 'realm point trade-in', 'medallion merchant',
                  'necklace vendor', 'master trainer', 'effect master'}
NOT_165_NAMES = {'bound sluagh wisp', 'sir lukas', 'cruella de vil', 'mercenary iuskedaro'}
# merchant lists of Atlas end-game "orb" gear / world items / launch rewards / medallions / seals - their NPCs go with
# them. (The Shrouded Isles' faction flights - dragonflies, wyverns, gryphons - stay: patch 1.65 added Inishail Island,
# Modernagrav and Allta Fearann with those stable masters; Allakhazam zone notes, CapnBry radar sightings.)
NOT_165_LISTS = ('orbs', 'worldalbionmerchant', 'worldhiberniamerchant', 'worldmidgardmerchant', 'launch_rewards',
                 'ofmerchant', 'kulodf', 'albrvrcraftinglist')
# crafting masters / registrars / emblemeers are 1.65 town NPCs (crafting came with Shrouded Isles' era patches)
ROLES_MORE = {'ArmorCraftingMaster': 'craftmaster', 'WeaponCraftingMaster': 'craftmaster', 'AlchemistsMaster': 'craftmaster',
              'SpellCraftingMaster': 'craftmaster', 'FletchingMaster': 'craftmaster', 'TailoringMaster': 'craftmaster',
              'NameRegistrar': 'registrar', 'GuildRegistrar': 'registrar', 'EmblemNPC': 'emblemeer', 'Recharger': 'recharger'}
FIELDS = ('Mob_ID,Name,Guild,Level,Realm,ClassType,Model,Size,Gender,X,Y,Z,Heading,AggroLevel,AggroRange,'
          'RoamingRange,Flags,ItemsListTemplateID,EquipmentTemplateID,FactionID,BodyType,NPCTemplateID,Speed,'
          'Strength,Constitution,Dexterity,Quickness,MeleeDamageType,RespawnInterval,Race,PathID')


def con_table():
    """capnbry.net/daoc/concolors.html as the old server encodes it (gameutils/ConLevels.cs): per player level, the
    run lengths of each colour from NPC level 0 upwards; past the table it is purple. Levels above 50 shift by one."""
    data = [
        {0: 1, 1: 1, 2: 1}, {-1: 1, 0: 1, 1: 1, 2: 1}, {-2: 1, -1: 1, 0: 1, 1: 1, 2: 1},
        {-3: 1, -2: 1, -1: 1, 0: 1, 1: 1, 2: 1}]
    data += [{-3: n, -2: 1, -1: 1, 0: 1, 1: 1, 2: 1} for n in range(2, 8)]           # 4..9
    data += [{-3: 7, -2: 1, -1: 2, 0: 1, 1: 1, 2: 2}, {-3: 7, -2: 1, -1: 2, 0: 2, 1: 2, 2: 2}]
    data += [{-3: n, -2: 2, -1: 2, 0: 2, 1: 2, 2: 2} for n in (7, 8, 9, 10, 11, 12, 13, 14)]   # 12..19
    data += [{-3: 14, -2: 2, -1: 3, 0: 2, 1: 2, 2: 3}, {-3: 14, -2: 2, -1: 3, 0: 3, 1: 3, 2: 3}]
    data += [{-3: n, -2: 3, -1: 3, 0: 3, 1: 3, 2: 3} for n in range(14, 27)]        # 22..34
    data += [{-3: 26, -2: 3, -1: 3, 0: 4, 1: 4, 2: 3}, {-3: 26, -2: 3, -1: 3, 0: 5, 1: 5, 2: 4},
             {-3: 26, -2: 4, -1: 3, 0: 5, 1: 5, 2: 5}, {-3: 26, -2: 4, -1: 4, 0: 5, 1: 5, 2: 5},
             {-3: 26, -2: 4, -1: 5, 0: 5, 1: 5, 2: 5}]
    data += [{-3: n, -2: 5, -1: 5, 0: 5, 1: 5, 2: 5} for n in range(26, 37)]        # 40..50
    assert len(data) == 51, len(data)
    table = []
    for runs in data:
        row = []
        for colour in sorted(runs):
            row += [colour] * runs[colour]
        table.append(row)                                    # npc levels past the row's end are purple (3)
    return table


def csv_values(text):
    """The old server's Util.SplitCSV(text, rearrange: true): '0-2' -> [0, 1, 2], '25;23;24' / '1,3' -> each."""
    out = []
    for part in str(text or '').replace(';', ',').split(','):
        part = part.strip()
        if '-' in part[1:]:
            a, b = part.split('-', 1)
            if a.strip().isdigit() and b.strip().isdigit():
                out += list(range(int(a), int(b) + 1))
                continue
        if part.isdigit():
            out.append(int(part))
    return out


HEALS = {'Heal', 'CombatHeal', 'HealOverTime', 'OmniHeal', 'SpreadHeal', 'PBAoEHeal', 'MercHeal'}
NPC_SPELLS = ROOT / 'godot/content/spells/npc_spells.json'


def spell_row(db, sid):
    cols = [r[1] for r in db.execute('pragma table_info(Spell)')]
    r = db.execute('select * from Spell where SpellID=?', (sid,)).fetchone()
    return {k.lower(): v for k, v in zip(cols, r) if k not in ('LastTimeRowUpdated', 'Spell_ID', 'PackageID')} if r else None


# Old-DB NPCs whose spot was recorded on the later client's village layout (owner 2026-10-10 "put her in that house
# instead of facing the wall"): {(name, X, Y): (X, Y, Z, heading)} global units. Laridia the Minstrel stood against
# the east wall of Cotswold's Tower / House (the later client moved that house 2400 units away): she goes inside, on
# the ground floor 4.5 m in from the north doorway, facing it (bhouse2 floor at +0.5 m).
NPC_MOVES = {('Laridia the Minstrel', 562253, 512261): (561950, 512136, 2460, 2048)}


def martial_factor(db, ids):
    """GameNPC.AutoSetStats' martial stat penalty for monster casters: harmful cast-time spells count 2, each instant
    harmful spell 1, heal spells 1, each instant heal 1, each other spell (and instant one) 1; exactly 1 -> no penalty,
    otherwise STR / CON / QUI x 0.85 ^ count."""
    harmful = instant_harmful = heals = instant_heals = misc = 0
    for sid in ids:
        sp = spell_row(db, sid)
        if sp is None:
            continue
        instant = not (sp.get('casttime') or 0)
        if str(sp.get('target', '')).lower() in ('enemy', 'area', 'cone'):
            if instant:
                instant_harmful += 1
            else:
                harmful = 1
        elif sp.get('type') in HEALS:
            if instant:
                instant_heals += 1
            else:
                heals = 1
        else:
            misc += 1
    count = harmful * 2 + instant_harmful + heals + instant_heals + misc
    return 1.0 if count == 1 else round(0.85 ** count, 6)


def export_npc_spells(db, ids):
    """Monster spells (and the spells their procs / sub-spells cast) into content/spells/npc_spells.json, merged."""
    import json as _json
    out = _json.loads(NPC_SPELLS.read_text(encoding='utf-8')) if NPC_SPELLS.exists() else {}
    todo = set(ids)
    while todo:
        sid = todo.pop()
        if str(sid) in out:
            continue
        sp = spell_row(db, sid)
        if sp is None:
            continue
        out[str(sid)] = sp
        for nxt in (sp.get('subspellid') or 0, sp.get('value') if sp.get('type') in ('OffensiveProc', 'DefensiveProc') else 0):
            if nxt and int(nxt) > 0 and str(int(nxt)) not in out:
                todo.add(int(nxt))
    # icons the client's way (as build_classes.py): spells.csv by client effect -> icons.csv -> sheet icon + border
    import csv, io
    from daoc_mpk import read_mpk
    from assets_pipeline import CLIENT
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    tab = lambda n: {r[0].strip(): r for r in csv.reader(io.StringIO(g[n].decode('latin1'))) if r and r[0].strip().isdigit()}
    icons, csp = tab('icons.csv'), tab('spells.csv')
    for sp in out.values():
        row = csp.get(str(sp.get('clienteffect') or sp.get('icon') or 0))
        r = icons.get(row[2].strip()) if row else None
        sp['icon_base'] = int(r[2]) if r and r[2].strip().lstrip('-').isdigit() else 0
        sp['icon_border'] = int(r[3]) if r and r[3].strip().lstrip('-').isdigit() else -1
    NPC_SPELLS.parent.mkdir(parents=True, exist_ok=True)
    NPC_SPELLS.write_text(_json.dumps(out, indent=1), encoding='utf-8')


STYLE_COLS = ['StyleID', 'ID', 'ClassId', 'Name', 'SpecKeyName', 'Icon', 'OpeningRequirementType',
              'OpeningRequirementValue', 'AttackResultRequirement', 'GrowthRate', 'BonusToHit', 'BonusToDefense',
              'TwoHandAnimation', 'RandomProc', 'StealthRequirement']


def template_styles(db, text):
    """NpcTemplate.Styles "styleID|classID;..." -> Style rows' StyleID (SkillBase.GetStyleByID(ID, ClassId)). As the
    old parser: an entry without both parts is skipped, an unknown pair gives nothing."""
    out = []
    for part in str(text or '').split(';'):
        bits = part.strip().split('|')
        if len(bits) != 2 or not bits[0].strip() or not bits[1].strip():
            continue
        r = db.execute('select StyleID from Style where ID=? and ClassId=?', (int(bits[0]), int(bits[1]))).fetchone()
        if r:
            out.append(int(r[0]))
    return out


def npc_style_rows(db, ids):
    """The monsters' styles (columns as build_classes.py) with their procs (StyleXSpell) and the animation the client
    plays (styles.csv by Icon / TwoHandAnimation)."""
    if not ids:
        return {}
    import csv, io
    from daoc_mpk import read_mpk
    from assets_pipeline import CLIENT
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    cst = {r[0].strip(): r for r in csv.reader(io.StringIO(g['styles.csv'].decode('latin1'))) if r and r[0].strip().isdigit()}
    out = {}
    for sid in sorted(ids):
        r = db.execute(f'select {",".join(STYLE_COLS)} from Style where StyleID=?', (sid,)).fetchone()
        if r is None:
            continue
        s = dict(zip([c.lower() for c in STYLE_COLS], r))
        s['procs'] = [{'spell': int(a), 'class': int(b or 0), 'chance': int(c or 0)} for a, b, c in
                      db.execute('select SpellID, ClassID, Chance from StyleXSpell where StyleID=?', (sid,))]
        row = cst.get(str(s.get('icon') or 0))
        s['animation'] = int(row[3]) if row and row[3].strip().isdigit() else 0
        row2 = cst.get(str(s.get('twohandanimation') or 0))
        s['animation_2h'] = int(row2[3]) if row2 and row2[3].strip().isdigit() else s['animation']
        out[str(sid)] = s
    return out


def emissary_spawns(zone):
    """The three faction emissaries (build_emissaries.py) - the ONLY custom, non-1.65 NPCs (owner 2026-10-09)."""
    f = ROOT / 'godot/content/quests/emissaries.json'
    if not f.exists():
        return []
    out = []
    for realm, e in json.loads(f.read_text(encoding='utf-8'))['emissaries'].items():
        if int(e['zone']) != zone:
            continue
        out.append({'id': 'emissary_%s' % realm, 'name': e['name'], 'guild': e['guild'], 'level': 50, 'realm': int(realm),
                    'role': 'emissary', 'trains': None, 'class_type': 'FactionEmissaryNPC', 'model': e['model'],
                    'size': e['size'], 'gender': e['gender'], 'pos': e['pos'], 'heading': e['heading'],
                    'aggro_level': 0, 'aggro_range': 0, 'roam': 0, 'flags': 16, 'speed': 0, 'items': '', 'equipment': '',
                    'faction': 0, 'body_type': 0, 'template': 0, 'stats': [0, 0, 0, 0], 'damage_type': 2, 'respawn': 0,
                    'race': 0, 'defense': [0, 0, 0, 0], 'spells': [], 'martial': 0, 'abilities': [], 'levels': [50],
                    'models': [e['model']], 'sizes': [e['size']], 'tether': 0, 'styles': [], 'custom': True})
    return out


def main():
    zone = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--zone=')), 200))
    sec = dict(line.split('=', 1) for line in zone_section(zone).splitlines() if '=' in line)
    region = int(sec['region'])
    x0, y0 = int(sec['region_offset_x']) * 8192, int(sec['region_offset_y']) * 8192
    x1, y1 = x0 + int(sec['width']) * 8192, y0 + int(sec['height']) * 8192
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    cols = FIELDS.split(',')
    rows = db.execute(f'select {FIELDS} from Mob where Region=? and X>=? and X<? and Y>=? and Y<?',
                      (region, x0, x1, y0, y1)).fetchall()
    # the old 0.35 bestiary import (PackageID 'BestiaryG9', 2026-10-08) turned named FRIENDLY npcs from the period
    # bestiary lists into realm-0 aggressive monsters standing among the real ones: the Camelot Hills "commander" on
    # top of the Albion Commander, six "innocent" in region 246 beside the Midgard ones (owner 2026-10-10: our import's
    # error, not 1.65 data). Dropped: a BestiaryG9 realm-0 mob named like a realm npc of the same region.
    import_copies = {r[0] for r in db.execute(
        "select b.Mob_ID from Mob b where b.PackageID='BestiaryG9' and coalesce(b.Realm,0)=0 and b.Region=? and exists "
        "(select 1 from Mob f where f.Region=b.Region and lower(f.Name)=lower(b.Name) and coalesce(f.Realm,0)<>0)",
        (region,))}
    rows = [r for r in rows if dict(zip(cols, r))['Mob_ID'] not in import_copies]
    spawns, equip_ids = [], set()
    tcols = ['Name', 'GuildName', 'Level', 'Model', 'Size', 'MaxSpeed', 'Flags', 'MeleeDamageType', 'AggroLevel',
             'AggroRange', 'BodyType', 'TetherRange', 'ReplaceMobValues', 'Gender', 'EquipmentTemplateID',
             'EvadeChance', 'ParryChance', 'BlockChance', 'LeftHandSwingChance', 'Spells', 'Race', 'Abilities',
             'Styles']
    templates = {r[0]: dict(zip(tcols, r[1:])) for r in db.execute(f'select TemplateId, {",".join(tcols)} from NpcTemplate')}
    for r in rows:
        m = dict(zip(cols, r))
        # the old server's GameNPC.LoadTemplate: TetherRange always comes from the template; with ReplaceMobValues
        # the template also replaces name, guild, level (a list / range rolled at every spawn), model and size
        # (lists, one picked), speed, flags, damage type, aggro level / range, body type and gender
        t = templates.get(m['NPCTemplateID']) if m['NPCTemplateID'] else None
        m['TetherRange'] = (t['TetherRange'] or 0) if t else 0
        # ...and so do the defences (GameNPC.HandleTemplateOnlyProperties): evade / parry / block %, left-hand swings
        m['Defense'] = [(t[k] or 0) if t else 0 for k in ('EvadeChance', 'ParryChance', 'BlockChance', 'LeftHandSwingChance')]
        # the template's spells (GameNPC.LoadTemplate -> HandleSpells, whatever ReplaceMobValues says)
        m['Spells'] = [int(x) for x in str((t or {}).get('Spells') or '').replace(',', ';').split(';') if x.strip().isdigit()]
        # GameNPC.LoadFromDatabase: a mob's damage type 0 is Slash; a template that replaces it keeps its own (0 = Natural)
        if not m['MeleeDamageType']:
            m['MeleeDamageType'] = 2
        # the template's abilities (GameNPC.LoadTemplate -> HandleAbilities: "Name|level;..."), e.g. CCImmunity
        m['Abilities'] = [a.split('|')[0].strip() for a in str((t or {}).get('Abilities') or '').split(';') if a.strip()]
        # the template's combat styles (GameNPC.LoadTemplate -> Styles, NpcStyleComponent picks them)
        m['Styles'] = template_styles(db, (t or {}).get('Styles'))
        m['Levels'] = [m['Level'] or 0]
        m['Models'] = [m['Model'] or 0]
        m['Sizes'] = [m['Size'] or 50]
        if t and t['ReplaceMobValues']:
            m['Name'] = t['Name'] or m['Name']
            m['Guild'] = t['GuildName'] if t['GuildName'] is not None else m['Guild']
            m['Levels'] = csv_values(t['Level']) or m['Levels']
            m['Models'] = csv_values(t['Model']) or m['Models']
            m['Sizes'] = csv_values(t['Size']) or m['Sizes']
            m['Model'], m['Size'], m['Level'] = m['Models'][0], m['Sizes'][0], m['Levels'][0]
            for k_mob, k_t in (('Speed', 'MaxSpeed'), ('Flags', 'Flags'), ('MeleeDamageType', 'MeleeDamageType'),
                               ('AggroLevel', 'AggroLevel'), ('AggroRange', 'AggroRange'), ('BodyType', 'BodyType'),
                               ('Gender', 'Gender'), ('Race', 'Race')):
                m[k_mob] = t[k_t]
            if t['EquipmentTemplateID']:
                m['EquipmentTemplateID'] = t['EquipmentTemplateID']
        cls = str(m['ClassType'] or '').split('.')[-1]
        if cls in NOT_165 or str(m['Guild'] or '').lower() in NOT_165_GUILDS or str(m['Name'] or '').lower() in NOT_165_NAMES \
                or str(m['ItemsListTemplateID'] or '').lower().startswith(NOT_165_LISTS):
            continue
        role, trains = ROLES.get(cls) or ROLES_MORE.get(cls), TRAINERS.get(cls)
        if trains is None and cls.endswith('Trainer') and '.Trainer.' in str(m['ClassType'] or ''):
            trains = {'AlbionRogueTrainer': 'AlbionRogue', 'MidgardRogueTrainer': 'MidgardRogue'}.get(cls, cls[:-len('Trainer')])
        if trains:
            role = 'trainer'
        if m['ItemsListTemplateID'] and role is None:
            role = 'merchant'
        lx, ly = m['X'] - x0, m['Y'] - y0
        # the old DB's Guild column also holds developer notes ('Part of Against the Grain Quest' - quests the
        # server scripted later): not a title the client showed (owner 2026-10-10)
        guild = '' if re.match(r'(?i)part of .* quest$', m['Guild'] or '') else (m['Guild'] or '')
        s = {'id': m['Mob_ID'], 'name': m['Name'], 'guild': guild, 'level': m['Level'] or 0,
             'realm': m['Realm'] or 0, 'role': role, 'trains': trains, 'class_type': cls,
             'model': str((m['Model'] or 0) & 0x7FFF), 'size': m['Size'] or 50, 'gender': m['Gender'] or 0,
             'pos': [round(lx * M, 3), round((m['Z'] or 0) * M, 3), round(ly * M, 3)],
             'heading': m['Heading'] or 0, 'aggro_level': m['AggroLevel'] or 0, 'aggro_range': m['AggroRange'] or 0,
             'roam': m['RoamingRange'] or 0, 'flags': m['Flags'] or 0, 'speed': m['Speed'] or 0,
             'items': m['ItemsListTemplateID'] or '', 'equipment': m['EquipmentTemplateID'] or '',
             'faction': m['FactionID'] or 0, 'body_type': m['BodyType'] or 0, 'template': m['NPCTemplateID'] or 0,
             # combat (the engine's own rules, numbers from build_rules.py): stats, damage type, respawn seconds
             'stats': [m['Strength'] or 0, m['Constitution'] or 0, m['Dexterity'] or 0, m['Quickness'] or 0],
             'damage_type': m['MeleeDamageType'] or 0, 'respawn': m['RespawnInterval'] or 0, 'race': m['Race'] or 0,
             'defense': m['Defense'],
             'spells': m['Spells'], 'martial': martial_factor(db, m['Spells']), 'abilities': m['Abilities'],
             'levels': m['Levels'], 'models': [str(int(x) & 0x7FFF) for x in m['Models']], 'sizes': m['Sizes'],
             'tether': m['TetherRange'], 'styles': m['Styles']}
        mv = NPC_MOVES.get((m['Name'], m['X'], m['Y']))
        if mv:
            s['pos'] = [round((mv[0] - x0) * M, 3), round(mv[2] * M, 3), round((mv[1] - y0) * M, 3)]
            s['heading'] = mv[3]
        # a patrol (Mob.PathID -> Path / PathPoints; NpcMovementComponent.MoveOnPath): its points in zone metres, each
        # point's MaxSpeed and WaitTime (tenths of a second); type 1 once, 2 back and forth, 3 loop
        if m['PathID']:
            pt = db.execute('select PathType from Path where PathID=?', (m['PathID'],)).fetchone()
            pts = [[round((x - x0) * M, 3), round((z or 0) * M, 3), round((y - y0) * M, 3), int(sp or 0), int(w or 0)]
                   for x, y, z, sp, w in db.execute('select X, Y, Z, MaxSpeed, WaitTime from PathPoints where PathID=? '
                                                    'order by Step', (m['PathID'],))]
            if pts:
                s['path'] = {'type': int(pt[0]) if pt else 3, 'points': pts}
        for eq in str(s['equipment'] or '').split(';'):          # template inventories list several (one per spawn)
            if eq.strip():
                equip_ids.add(eq.strip())
        spawns.append(s)
    # (the three faction emissaries - build_emissaries.py - were the only custom NPCs; owner 2026-10-09: removed, strict
    # 1.65 for now. emissary_spawns() stays for if they come back)
    styles = npc_style_rows(db, {i for sp in spawns for i in sp['styles']})
    # MobXAmbientBehaviour (MobAmbientBehaviourManager: by name, any case): what monsters / NPCs say on a trigger
    names = {str(sp['name']).lower() for sp in spawns}
    ambient = {}
    for src, trig, emote, text, chance, voice in db.execute(
            'select Source, Trigger, Emote, Text, Chance, Voice from MobXAmbientBehaviour'):
        if str(src or '').lower() in names:
            ambient.setdefault(str(src).lower(), []).append({'trigger': trig, 'emote': int(emote or 0), 'text': text or '',
                                                             'chance': int(chance or 0), 'voice': voice or ''})
    export_npc_spells(db, {sid for sp in spawns for sid in sp['spells']} |
                      {int(p['spell']) for s in styles.values() for p in s['procs']})
    equipment = {}
    for t in sorted(equip_ids):
        equipment[t] = [{'slot': a, 'model': b, 'color': c, 'effect': d, 'extension': e} for a, b, c, d, e in
                        db.execute('select Slot,Model,Color,Effect,Extension from NPCEquipment where TemplateID=?', (t,))]
    out = ROOT / f'godot/content/zones/zone{zone:03d}/npcs.json'
    meta = {'zone': zone, 'source': 'old OfflineDAoC DB Mob table (vetted 1.65 spawns), read only',
            'spawns': spawns, 'equipment': equipment, 'con': con_table(), 'styles': styles,
            'ambient': ambient,
            'examine': {'target': 'You target [{name}].', 'target_article': 'You target the [{name}].',
                        'base': 'You examine {name}. {pronoun} is {stance}{suffix}',
                        'stance': {'friendly': 'friendly', 'neutral': 'neutral towards you',
                                   'aggressive': 'aggressive towards you'},
                        'end': {'friendly': '.', 'neutral': '.', 'aggressive': '!'},
                        'suffix': {'merchant': ' and is a merchant', 'guard': ' and is a guard',
                                   'healer': ' and is a healer', 'smith': ' and is a smith',
                                   'enchanter': ' and is an enchanter', 'hastener': ' and is a hastener',
                                   'vaultkeeper': ' and is a vaultkeeper',
                                   'trainer': ' and trains members of the {trains} class'},
                        'source': 'period chat logs quoted on Allakhazam (stance wording, "!" on aggressive); role '
                                  'suffixes from the old server language files'}}
    out.write_text(json.dumps(meta, indent=1), encoding='utf-8')
    from collections import Counter
    print(len(spawns), 'spawns;', Counter(s['role'] or ('monster' if s['realm'] == 0 else 'npc') for s in spawns))


if __name__ == '__main__':
    main()
