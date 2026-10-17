"""Audit the client effects the server's boss scripts use (2026-10-13, owner: "the dragon breathed on me but I didn't
get any spell effect ... make sure all boss effects from summoner's hall, darkness falls, and all 3 dungeons and their
sound effects are properly ported"). Read only: the shared server's scripts/namedmobs/<area> C# (spells built in code
- ClientEffect = n; DB spells by id - GetSpellByID(n) / SkillBase spells; direct SendSpellEffectAnimation /
SendSpellCastAnimation calls with a literal id) and its database. Each client effect is checked like
audit_class_fx.py: a spells.csv row in spell_fx.json, every piece's NIF converted, its sound set exported.

    python pipeline/audit_boss_fx.py [area ...]     (default: Dragons DarknessFalls SummonersHall CaerSidi
                                                     Galladoria TuscarianGlacier)
"""
import json, re, sqlite3, sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GODOT = ROOT / 'godot'
SERVER = ROOT.parent / 'new class test - CLAUDE VERSION'
SCRIPTS = SERVER / 'development-source/server/GameServer/scripts/namedmobs'
DB = SERVER / 'runtime/data/opendaoc.sqlite3.db'
AREAS = sys.argv[1:] or ['Dragons', 'DarknessFalls', 'SummonersHall', 'CaerSidi', 'Galladoria', 'TuscarianGlacier']

fx = json.loads((GODOT / 'content/spells/spell_fx.json').read_text(encoding='utf-8'))
sounds = json.loads((GODOT / 'content/sounds/sounds.json').read_text(encoding='utf-8'))
con = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)

CE = re.compile(r'ClientEffect\s*=\s*(\d+)')
BYID = re.compile(r'GetSpellByID\(\s*(\d+)\s*\)')
ANIM = re.compile(r'Send(?:Spell(?:Effect|Cast)Animation)\s*\(([^;]*?)\)\s*;')
NUM = re.compile(r'\b(\d{2,5})\b')


def check(ce):
    """[] when the effect plays fully, else what's missing."""
    e = fx['effects'].get(str(ce))
    if e is None:
        return ['no spells.csv row (nothing plays)']
    bad = []
    pieces = list(e['gather']) + list(e['cast_fx']) + [e[k] for k in ('projectile', 'target', 'buildup', 'pulse', 'radius', 'resist') if e[k]]
    if not pieces:
        bad.append('no effect pieces at all')
    for p in pieces:
        f = fx['fx'].get(str(p))
        if f is None:
            bad.append(f'piece {p} not built')
            continue
        if not (GODOT / f['nif'].replace('res://', '')).exists():
            bad.append(f"piece {p} {f['name']} not converted")
    if e.get('sound_set') and str(int(e['sound_set'])) not in sounds.get('spells', {}):
        bad.append(f"sound set {e['sound_set']} not exported")
    return bad


report = {}
for area in AREAS:
    files = sorted((SCRIPTS / area).rglob('*.cs')) if (SCRIPTS / area).exists() else []
    uses = defaultdict(set)                                # client effect -> files
    for f in files:
        src = f.read_text(encoding='utf-8', errors='ignore')
        for m in CE.finditer(src):
            uses[int(m.group(1))].add(f.stem)
        for m in BYID.finditer(src):
            r = con.execute('select ClientEffect from Spell where SpellID=?', (int(m.group(1)),)).fetchone()
            if r and r[0]:
                uses[int(r[0])].add(f.stem + f' (spell {m.group(1)})')
        for m in ANIM.finditer(src):
            for n in NUM.findall(m.group(1)):
                if int(n) > 50:                            # a literal effect id among the arguments
                    uses[int(n)].add(f.stem + ' (animation)')
    rows = []
    for ce in sorted(uses):
        e = fx['effects'].get(str(ce))
        rows.append({'effect': ce, 'by': sorted(uses[ce]), 'problems': check(ce),
                     'pieces': None if e is None else [fx['fx'].get(str(p), {}).get('name', p) for p in
                                                       [e[k] for k in ('target', 'radius', 'projectile') if e[k]]]})
    report[area] = rows
    bad = [r for r in rows if r['problems']]
    print(f'== {area}: {len(files)} scripts, {len(rows)} client effects, {len(bad)} with problems')
    for r in bad:
        print(f"   {r['effect']}: {'; '.join(r['problems'])}  <- {', '.join(r['by'][:4])}")
(HERE / 'audit_boss_fx.json').write_text(json.dumps(report, indent=1), encoding='utf-8')
