"""The Claude version server's character classes for the create screen (Offline DAoC Rebuilt, owner 2026-10-11).

The game is a client of the old server, so character creation must offer exactly what that server accepts: its
classes (not 1.65 "ways" - the old client picked the class itself), each class's races, its three stats (the server
checks the 30 creation points against them) and the classes the server has switched off (ServerProperty
disabled_classes). Read from the old server's own source and database:
  external/old_project/development-source/server/GameServer/playerclasses/*/Class*.cs
  external/old_project/development-source/server/GameServer/Enums/eCharacterClass.cs, GlobalConstants.cs
  ../new class test - CLAUDE VERSION/runtime/data/opendaoc.sqlite3.db - the shared server's database, read only
  (ServerProperty disabled_classes / disabled_races)
Writes godot/content/rules/server_classes.json.

    python pipeline/build_server_classes.py
"""
import json
import re
import sqlite3
from pathlib import Path

TOP = Path(__file__).resolve().parent.parent
GS = TOP / 'external/old_project/development-source/server/GameServer'
OUT = TOP / 'godot/content/rules/server_classes.json'
DB = TOP.parent / 'new class test - CLAUDE VERSION/runtime/data/opendaoc.sqlite3.db'   # the shared server (0.36 / b / c)

RACES = {'Briton': 1, 'Avalonian': 2, 'Highlander': 3, 'Saracen': 4, 'Norseman': 5, 'Troll': 6, 'Dwarf': 7,
         'Kobold': 8, 'Celt': 9, 'Firbolg': 10, 'Elf': 11, 'Lurikeen': 12, 'Inconnu': 13, 'Valkyn': 14, 'Sylvan': 15,
         'HalfOgre': 16, 'Frostalf': 17, 'Shar': 18, 'Korazh': 19, 'Deifrang': 20, 'Graoch': 21}
# the base classes ("ways") - the server still lists them as starting classes, the old client offered the classes
BASE = {'Fighter', 'Elementalist', 'Acolyte', 'AlbionRogue', 'Mage', 'Disciple', 'Viking', 'Mystic', 'Seer',
        'MidgardRogue', 'Magician', 'Guardian', 'Naturalist', 'Stalker', 'Forester'}


def enum_values(path, name):
    text = path.read_text(encoding='utf-8', errors='replace')
    body = text[text.index('enum ' + name):]
    body = body[body.index('{') + 1:body.index('}')]
    out = {}
    value = -1
    for line in body.splitlines():
        line = line.split('//')[0].strip().rstrip(',')
        if not line:
            continue
        m = re.match(r'(\w+)\s*(?:=\s*(\w+))?', line)
        if not m:
            continue
        if m.group(2) is not None:
            value = int(m.group(2), 0) if re.match(r'^(0x)?[0-9a-fA-F]+$', m.group(2)) else out[m.group(2)]
        else:
            value += 1
        out[m.group(1)] = value
    return out


def parse_classes():
    classes = {}
    for f in sorted((GS / 'playerclasses').rglob('Class*.cs')):
        t = f.read_text(encoding='utf-8', errors='replace')
        t = re.sub(r'//[^\n]*', '', t)
        m = re.search(r'\[CharacterClass\(\(int\)eCharacterClass\.(\w+)\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"(?:\s*,\s*"([^"]*)")?', t)
        cm = re.search(r'class\s+(Class\w+)\s*:\s*(\w+)', t)
        if not m or not cm:
            continue
        stats = {k: (re.search(r'm_%sStat\s*=\s*eStat\.(\w+)' % k, t) or [None, None])[1]
                 for k in ('primary', 'secondary', 'tertiary')}
        races = None
        rm = re.search(r'EligibleRaces\s*=>\s*new\s+List<PlayerRace>\(\)\s*\{(.*?)\}', t, re.S)
        if rm:
            races = [RACES[r] for r in re.findall(r'PlayerRace\.(\w+)', rm.group(1)) if r in RACES]
        classes[cm.group(1)] = {'enum': m.group(1), 'name': m.group(2), 'base': m.group(3),
                                'female': m.group(4) or m.group(2), 'parent': cm.group(2), 'stats': stats, 'races': races}
    for k, c in classes.items():                          # inherit what a class leaves to its base class
        p = classes.get(c['parent'])
        while p:
            for s in ('primary', 'secondary', 'tertiary'):
                c['stats'][s] = c['stats'][s] or p['stats'][s]
            c['races'] = c['races'] if c['races'] is not None else p['races']
            p = classes.get(p['parent'])
    return classes


def starting_classes():
    t = (GS / 'GlobalConstants.cs').read_text(encoding='utf-8', errors='replace')
    block = t[t.index('STARTING_CLASSES_DICT'):]
    block = block[:block.index('};')]
    out = {}
    for realm, body in re.findall(r'eRealm\.(\w+),\s*new List<eCharacterClass>\(\)\s*\{(.*?)\}\}', block, re.S):
        body = re.sub(r'//[^\n]*', '', body)
        seen = []
        for c in re.findall(r'eCharacterClass\.(\w+)', body):
            if c not in seen:
                seen.append(c)
        out[realm] = seen
    return out


def id_set(text):
    ids = set()
    for part in re.split(r'[;,]', text or ''):
        part = part.strip()
        if '-' in part:
            a, b = part.split('-')
            ids.update(range(int(a), int(b) + 1))
        elif part.isdigit():
            ids.add(int(part))
    return ids


def main():
    ids = enum_values(GS / 'Enums/eCharacterClass.cs', 'eCharacterClass')
    classes = {c['enum']: c for c in parse_classes().values()}
    db = sqlite3.connect(DB.as_uri() + '?mode=ro', uri=True)
    prop = dict(db.execute("SELECT Key, Value FROM ServerProperty WHERE Key IN ('disabled_classes','disabled_races')"))
    disabled = id_set(prop.get('disabled_classes'))
    disabled_races = id_set(prop.get('disabled_races'))
    realms = {'Albion': 'alb', 'Midgard': 'mid', 'Hibernia': 'hib'}
    out = {'realms': {}, 'classes': {}}
    for realm, names in starting_classes().items():
        listed = []
        for n in names:
            c = classes.get(n)
            if c is None or n in BASE or ids[n] in disabled:
                continue
            races = [r for r in (c['races'] or []) if r not in disabled_races]
            if not races:
                continue
            listed.append(ids[n])
            # its primary / secondary / tertiary stats: where the create screen spends the 30 points (at level 1 the
            # server's CharacterStatValidator only checks that 30 points are spent above the race's stats)
            out['classes'][str(ids[n])] = {'name': c['name'], 'female': c['female'], 'realm': realms[realm],
                                           'races': races, 'stats': [c['stats'][s] for s in
                                                                     ('primary', 'secondary', 'tertiary')]}
        out['realms'][realms[realm]] = listed
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=1), encoding='utf-8')
    for r, l in out['realms'].items():
        print(r, [out['classes'][str(i)]['name'] for i in l])


if __name__ == '__main__':
    main()
