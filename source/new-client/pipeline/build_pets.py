"""Summoned pets: every NPC template a class summon spell calls up (Spell.LifeDrainReturn = NpcTemplate id, as the old
server's SummonSpellHandler reads it), for the engine's pets (game/combat/pets.gd).

    python build_pets.py          # after build_classes.py (spells.json)
Writes content/classes/pets.json:
  templates: {template id: {name, models [list - one picked], size, stat_pct [STR CON DEX QUI INT, 0 = autoset only],
              spells [ids], equipment [{slot, models [list]}], damage_type, race, body_type, speed, defense}}
  and adds the templates' spells to content/spells/npc_spells.json (the monsters' spell file; pets cast through it).
Equipment: a template's Inventory without ':' names NPCEquipment templates (one picked); with ':' it is the legacy
inline list "slot:model|model;..." (GameNPC.LoadTemplate HandleInventory) - both resolved here."""
import json, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT
import build_npcs

DB = ROOT / 'external/old_project/runtime/data/opendaoc.sqlite3.db'
SPELLS = ROOT / 'godot/content/classes/spells.json'
OUT = ROOT / 'godot/content/classes/pets.json'
SUMMONS = ('SummonDruidPet', 'SummonUnderhill', 'SummonHunterPet', 'SummonSpiritFighter', 'SummonSimulacrum',
           'SummonNecroPet', 'SummonCommander', 'SummonMinion', 'SummonAnimistPet', 'SummonAnimistFnF',
           'SummonTheurgistPet', 'Bomber')


# PERIOD LOOKS (owner 2026-10-10, from period research - "PET APPEARANCE LEDGER.md"): the old server's templates gave the
# Necromancer pets Darkness Rising models and later shields, and the Bonedancer pets the later "Bonedancer" bone weapons,
# a commander helm and shields ("100% not accurate to 1.65" - owner). {template id: (models, equipment variants)};
# a variant is a list of (slot, model[, colour, effect]); [] = nothing worn or held.
def _v(*rows):
    return [{'slot': r[0], 'models': [r[1]], 'color': r[2] if len(r) > 2 else 0, 'effect': r[3] if len(r) > 3 else 0,
             'extension': 0} for r in rows]


# the commanders' 9 normal Midgard weapons (2003-2004: one picked at the summon): two-handers in slot 12, one-handers 10
COMMANDER_WEAPONS = [_v((12, 572)), _v((12, 576)), _v((10, 313)), _v((10, 310)), _v((10, 322)), _v((10, 319)),
                     _v((10, 320)), _v((10, 316)), _v((10, 578))]          # great sword, great hammer, bastard sword,
#                                       long sword, war hammer, war axe, small hammer, bearded axe, hand axe (objects.csv)
LEATHER = [(22, 303), (23, 304), (25, 300)]          # the Norse leather set the old templates gave them (kept: no data)
PERIOD = {
    # Necromancer
    200: ([110], [[]]), 201: ([110], [[]]), 202: ([110], [[]]),          # minor / lesser / zombie servant: 110 Zombie
    203: ([467], [[]]),                                                  # reanimated servant: 467 Briton undead male
    204: ([106], [[]]),                                                  # necroservant: 106 Roman Dead (Legionnaire)
    205: ([440], [[]]),                                                  # greater necroservant: 440 Blue Wight
    206: ([653], [_v((12, 6, 74, 30))]),                                 # abomination: 653 Glowing Demon Knight, 2H sword
    # Bonedancer commanders: 952 Bone Dancer Commander (all ranks, 2004 packet log), a normal weapon, no shield / helm
    49: ([952], COMMANDER_WEAPONS), 50: ([952], COMMANDER_WEAPONS), 51: ([952], COMMANDER_WEAPONS), 52: ([952], COMMANDER_WEAPONS),
}
# every minion: the grey 920 "Skeleton 2002" (owner 2026-10-10: "use the grey skeleton, that's what I remember" - a Nov
# 2004 log's 24 "Small Skeleton" for guardians / healers was medium confidence and looked wrong)
for _t in range(65, 71):                                                 # guardians (Bone Patroller line): a normal
    PERIOD[_t] = ([920], [_v((10, 321))])                                # 1H hammer
for _t in range(71, 77):                                                 # healers (Bonepatcher line): no weapon
    PERIOD[_t] = ([920], [_v(*LEATHER)])                                 # (Nov 2004 log; another list says a 2H hammer)
for _t in range(83, 89):                                                 # melee soldiers (Bonesmasher line): axes 1H / 2H
    PERIOD[_t] = ([920], [_v((10, 578), *LEATHER), _v((10, 319), *LEATHER), _v((12, 317), *LEATHER), _v((12, 577), *LEATHER)])
for _t in range(77, 83):                                                 # archers (Bone Dart line): the same bow + a sword
    PERIOD[_t] = ([920], [_v((10, 311), (13, 564), *LEATHER)])
for _t in range(53, 59):                                                 # mages (Bonemage line): a normal staff + robe
    PERIOD[_t] = ([920], [_v((12, 327), (25, 683))])
for _t in range(59, 65):                                                 # debuffers (Bonebreaker line): no period data -
    PERIOD[_t] = ([920], [_v((10, 311))])                                # a normal short sword in place of the bone sword


def split_list(s):
    return [x.strip() for x in str(s or '').replace(',', ';').split(';') if x.strip()]


def equipment(db, inventory):
    """[{slot, models}] choices for one summon (the named template picked at summon time: 'variants')."""
    inv = str(inventory or '')
    if not inv:
        return {'inline': [], 'variants': []}
    if ':' not in inv:
        variants = []
        for name in split_list(inv):
            rows = [{'slot': a, 'models': [b], 'color': c, 'effect': d, 'extension': e} for a, b, c, d, e in
                    db.execute('select Slot,Model,Color,Effect,Extension from NPCEquipment where TemplateID=?', (name,))]
            if rows:
                variants.append(rows)
        return {'inline': [], 'variants': variants}
    inline = []
    for part in split_list(inv):
        if ':' not in part:
            continue                                          # named entries are ignored in the inline form
        slot, models = part.split(':', 1)
        ms = [int(m) for m in models.split('|') if m.strip().isdigit() and int(m) > 0]
        if slot.strip().isdigit() and ms:
            inline.append({'slot': int(slot), 'models': ms})
    return {'inline': inline, 'variants': []}


def main():
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    spells = json.loads(SPELLS.read_text(encoding='utf-8'))
    tids = sorted({int(v.get('lifedrainreturn') or 0) for v in spells.values() if v.get('type') in SUMMONS} - {0})
    cols = ['Name', 'Model', 'Size', 'Level', 'Strength', 'Constitution', 'Dexterity', 'Quickness', 'Intelligence',
            'Spells', 'EquipmentTemplateID', 'MeleeDamageType', 'Race', 'BodyType', 'MaxSpeed', 'EvadeChance',
            'ParryChance', 'BlockChance', 'LeftHandSwingChance', 'Abilities', 'Styles']
    out, spell_ids, missing = {}, set(), []
    for tid in tids:
        r = db.execute(f'select {",".join(cols)} from NpcTemplate where TemplateId=?', (tid,)).fetchone()
        if r is None:
            missing.append(tid)
            continue
        t = dict(zip(cols, r))
        sp = [int(x) for x in split_list(t['Spells']) if x.isdigit()]
        spell_ids.update(sp)
        out[str(tid)] = {
            'name': t['Name'], 'models': [int(m) for m in split_list(t['Model']) if m.isdigit()],
            'size': [int(s) for s in split_list(t['Size']) if s.isdigit()] or [50],
            'stat_pct': [t['Strength'] or 0, t['Constitution'] or 0, t['Dexterity'] or 0, t['Quickness'] or 0,
                         t['Intelligence'] or 0],
            'spells': sp, 'equipment': equipment(db, t['EquipmentTemplateID']),
            'damage_type': t['MeleeDamageType'] or 0, 'race': t['Race'] or 0, 'body_type': t['BodyType'] or 0,
            'speed': t['MaxSpeed'] or 0,
            'defense': [t['EvadeChance'] or 0, t['ParryChance'] or 0, t['BlockChance'] or 0, t['LeftHandSwingChance'] or 0],
            'abilities': [a.split('|')[0].strip() for a in split_list(t['Abilities'])],
            # combat styles (the Bonedancer's commanders and bone fighters; NpcTemplate.Styles "styleID|classID")
            'styles': build_npcs.template_styles(db, t['Styles']),
        }
    for tid, (models, variants) in PERIOD.items():          # the period looks over the old server's templates
        if str(tid) in out:
            out[str(tid)]['models'] = models
            out[str(tid)]['equipment'] = {'inline': [], 'variants': [v for v in variants if v] if any(variants) else [],
                                          'source': 'period (build_pets.PERIOD)'}
    styles = build_npcs.npc_style_rows(db, {i for t in out.values() for i in t['styles']})
    spell_ids.update(int(p['spell']) for s in styles.values() for p in s['procs'])
    build_npcs.export_npc_spells(db, spell_ids)
    OUT.write_text(json.dumps({'source': 'old OfflineDAoC DB NpcTemplate / NPCEquipment (read only)', 'templates': out,
                               'styles': styles},
                              indent=1), encoding='utf-8')
    print(len(out), 'pet templates,', len(spell_ids), 'pet spells, missing templates', missing)


if __name__ == '__main__':
    main()
