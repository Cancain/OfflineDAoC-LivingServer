"""Audit one class's visuals in the Godot client against the client data (2026-10-13, owner: "Check all the sluaghbinder
spells and animations and make sure they come thru ... styles and taunts too"): every spell of its lines, its pets'
spells and its styles' procs -> the client effect (spells.csv row in the built spell_fx.json), each piece's effect NIF
converted, the sound set exported, the casting clips present on every race the class can be; every style -> its
animation in style_anims.json and the clip on the race figures.

    python pipeline/audit_class_fx.py 63          (class id; 63 = Sluaghbinder)
"""
import json, os, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GODOT = ROOT / 'godot'
DB = ROOT.parent / 'new class test - CLAUDE VERSION/runtime/data/opendaoc.sqlite3.db'

cls = int(sys.argv[1]) if len(sys.argv) > 1 else 63
con = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
fx = json.loads((GODOT / 'content/spells/spell_fx.json').read_text(encoding='utf-8'))
sounds = json.loads((GODOT / 'content/sounds/sounds.json').read_text(encoding='utf-8'))
styles_anim = json.loads((GODOT / 'content/rules/style_anims.json').read_text(encoding='utf-8'))
style_clips = json.loads((GODOT / 'content/characters/style_clips.json').read_text(encoding='utf-8'))
RACES = sys.argv[2].split(',') if len(sys.argv) > 2 else ['cel_m', 'cel_f', 'elf_m', 'elf_f', 'fir_m', 'fir_f', 'lur_m',
                                                         'lur_f', 'syl_m', 'syl_f']   # Hibernia's
race_clips = {r: set(json.loads((GODOT / f'content/characters/races/{r}/figure.json').read_text(encoding='utf-8'))
                     .get('clip_seconds', {})) for r in RACES}
mons = json.loads((GODOT / 'content/monsters/monsters.json').read_text(encoding='utf-8'))

specs = [r[0] for r in con.execute('select SpecKeyName from ClassXSpecialization where ClassID=?', (cls,))]
lines = [r[0] for r in con.execute(f"select SpellLineID from SpellLine where Spec in ({','.join('?' * len(specs))})", specs)]
spells = {}
for (sid,) in con.execute(f"select SpellID from LineXSpell where LineName in (select KeyName from SpellLine where SpellLineID in ({','.join('?' * len(lines))}))", lines):
    spells[int(sid)] = 'line'
# the races (figure prefixes) the class can be
races_rows = con.execute('select * from sqlite_master where name="ClassXRace"').fetchall()

def spell_row(sid):
    r = con.execute('select SpellID, Name, Type, ClientEffect, LifeDrainReturn, SubSpellID from Spell where SpellID=?', (sid,)).fetchone()
    return r

# pets the class summons (their templates' Spells) and sub-spells
for sid in list(spells):
    r = spell_row(sid)
    if r is None:
        continue
    if r[5]:
        spells.setdefault(int(r[5]), 'sub-spell of %s' % r[1])
    if 'Summon' in (r[2] or '') and r[4]:
        t = con.execute('select Name, Model, Spells from NpcTemplate where TemplateId=?', (r[4],)).fetchone()
        if t and t[2]:
            for x in str(t[2]).split(';'):
                if x.strip().isdigit():
                    spells.setdefault(int(x), 'pet %s' % t[0])
styles = con.execute(f"select ID, Name, SpecKeyName, Icon, SpecLevelRequirement from Style where ClassId=? or SpecKeyName in ({','.join('?' * len(specs))})",
                     [cls] + specs).fetchall()
for st in styles:
    for (sid,) in con.execute('select SpellID from StyleXSpell where StyleID=?', (st[0],)):
        spells.setdefault(int(sid), 'style %s' % st[1])

problems, ok = [], 0
fx_ids_all = set()
for sid in sorted(spells):
    r = spell_row(sid)
    if r is None:
        problems.append(f'spell {sid} ({spells[sid]}): not in the Spell table')
        continue
    _, name, typ, ce, *_ = r
    if not ce:
        continue
    e = fx['effects'].get(str(ce))
    if e is None:
        problems.append(f'{name} [{typ}] ({spells[sid]}): client effect {ce} has no spells.csv row in spell_fx.json')
        continue
    bad = []
    pieces = list(e['gather']) + list(e['cast_fx']) + [e[k] for k in ('projectile', 'target', 'buildup', 'pulse', 'radius', 'resist') if e[k]]
    for p in pieces:
        f = fx['fx'].get(str(p))
        if f is None:
            bad.append(f'piece {p} not built')
            continue
        fx_ids_all.add(p)
        path = GODOT / f['nif'].replace('res://', '')
        if not path.exists():
            bad.append(f"piece {p} {f['name']}: {path.parent.name} not converted")
    anims = [a for a in e.get('anims', []) if a]
    if typ not in ('StyleTaunt',) and spells[sid] == 'line' and len(anims) < 3:
        bad.append(f'casting clips {e.get("anims")} (not a full start / hold / release)')
    for a in anims:
        lacking = [r for r in RACES if a not in race_clips[r]]
        if lacking:
            bad.append(f'casting clip {a} missing on {lacking}')
    if e.get('sound_set') and str(int(e['sound_set'])) not in sounds.get('spells', {}):
        bad.append(f"sound set {e['sound_set']} not exported")
    if bad:
        problems.append(f'{name} [{typ}] ce {ce}: ' + '; '.join(bad))
    else:
        ok += 1

print(f'class {cls}: {len(spells)} spells ({ok} complete), {len(styles)} styles')
for st in styles:
    sid, name, spec, icon, lvl = st
    two = con.execute('select TwoHandAnimation from Style where ID=?', (sid,)).fetchone()
    for which, num in (('icon', icon), ('two-hand', two[0] if two else 0)):
        if not num:
            continue
        a = styles_anim.get(str(num))
        clip = style_clips.get(str(a)) if a is not None else None
        lacking = [r for r in RACES if clip and clip not in race_clips[r]]
        if a is None:
            problems.append(f'style {name} ({spec}): {which} {num} has no styles.csv row (no style animation)')
        elif clip is None:
            problems.append(f'style {name}: {which} {num} -> animation {a} has no clip name (style_clips.json)')
        elif lacking:
            problems.append(f'style {name}: clip {clip} missing on {lacking}')
        else:
            ok_styles = globals().get('ok_styles', 0) + 1
            globals()['ok_styles'] = ok_styles
print('styles with a working animation (icon / two-hand):', globals().get('ok_styles', 0))
print('PROBLEMS:' if problems else 'no problems')
for p in problems:
    print('  -', p)
