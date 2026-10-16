"""Spell visuals and sounds: the old client's tables cross-checked against what 0.36c built and plays (owner
2026-10-15: "check old client spell sounds, animations, effects ... flag any that seem wrong without changing them").
Read-only. For every client effect the server's spells use (DB Spell.ClientEffect):
  - casting animations (spells.csv Anim1-3 -> anims.csv columns): the clip exists on the race figures
  - every effect it names (gather 1A / 1B, cast 2 / 3, projectile, target, buildup, pulse, radius, resist): in
    speffects.csv, converted (godot/content/monsters/effects/<nif>/model.gltf) with its textures
  - the sound set (cc_spells.csv): each event's sound resolves to a sound file
  - client columns the game does not play (Pulse / Radius effects, Play Anims, CasterFX Focus, Remove Effect on Cast)
  - material patterns found 2026-10-14: additive layers with a mask in the dark slot (drawn flat / oversized), dark lit
    cut-outs (black-looking leaves)
Writes "SPELL FX AUDIT.md" in the project folder.

    python pipeline/audit_spell_fx.py
"""
import csv, io, json, sqlite3, re
from collections import defaultdict
from pathlib import Path
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk

G = ROOT / 'godot'
DB = ROOT / 'external/old_project/runtime/data/opendaoc.sqlite3.db'
OUT = ROOT / 'SPELL FX AUDIT.md'


def table(g, name):
    rows = list(csv.reader(io.StringIO(g[name].decode('latin1'))))
    return {r[0].strip(): r for r in rows if r and r[0].strip().isdigit()}, rows


def num(r, i):
    try:
        return int(float(r[i])) if i < len(r) and r[i].strip() else 0
    except ValueError:
        return 0


g = read_mpk(str(CLIENT / 'gamedata.mpk'))
spells, _ = table(g, 'spells.csv')
speffects, _ = table(g, 'speffects.csv')
anim_header = list(csv.reader(io.StringIO(g['anims.csv'].decode('latin1'))))[1]
fxjson = json.loads((G / 'content/spells/spell_fx.json').read_text(encoding='utf-8'))
ours_e, ours_fx = fxjson['effects'], fxjson['fx']
sounds = json.loads((G / 'content/sounds/sounds.json').read_text(encoding='utf-8'))

# the race figures' clips (every figure shares the Catacombs anim set; a clip missing on one is listed)
fig_clips = {}
for d in (G / 'content/characters/races').iterdir():
    fj = d / 'figure.json'
    if fj.exists():
        fig_clips[d.name] = set(json.loads(fj.read_text(encoding='utf-8')).get('clip_seconds', {}).keys())

# which client effects the server's spells use, and by which spells
db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
used = defaultdict(list)
for sid, name, ce, typ in db.execute('select SpellID, Name, ClientEffect, Type from Spell where ClientEffect > 0'):
    used[str(ce)].append(f'{name} ({typ})')


def sound_file_ok(name, depth=0):
    key = (name or '').strip().lower()
    if key in ('', 's_null') or depth > 4:
        return True
    if key.startswith('g_'):
        return all(sound_file_ok(m, depth + 1) for m in sounds['groups'].get(key, ['?missing']))
    if key.startswith('q_'):
        q = sounds['queues'].get(key)
        return q is not None and all(sound_file_ok(m, depth + 1) for m in q.get('members', []))
    row = sounds['named'].get(key) or sounds['named'].get('s_' + key)
    return row is not None and (G / 'content/sounds' / row['file']).exists()


def gltf_ok(path):
    p = G / path.replace('res://', '')
    if not p.exists():
        return 'not converted'
    doc = json.loads(p.read_text(encoding='utf-8'))
    missing = [i.get('uri') for i in doc.get('images', []) if i.get('uri') and not (p.parent / i['uri']).exists()]
    for part in doc.get('extras', {}).get('nif_particles', []):
        t = part.get('texture')
        if t and not any((p.parent / f'textures/{s}/{t}.png').exists() for s in ('x4plus', 'original')):
            missing.append(f'particle {t}')
    return ('textures missing: ' + ', '.join(sorted(set(missing))[:4])) if missing else ''


COLS = {'gather A': 6, 'gather B': 7, 'cast 2': 8, 'cast 3': 9, 'projectile': 10, 'target': 11, 'buildup': 12,
        'pulse': 13, 'radius': 15, 'resist': 16}
flags = defaultdict(list)      # section -> lines
unused = defaultdict(list)
mat_add_dark, mat_dark_cut = defaultdict(set), defaultdict(set)


def nif_of(fx_id):
    f = ours_fx.get(str(fx_id))
    return f.get('nif') if f else None


checked_nifs = {}
for ce, users in sorted(used.items(), key=lambda kv: int(kv[0])):
    r = spells.get(ce)
    who = f'{ce} {r[1].strip() if r else "?"} - used by {users[0]}' + (f' (+{len(users) - 1})' if len(users) > 1 else '')
    if r is None:
        flags['Client effect not in the client\'s spells.csv'].append(who)
        continue
    e = ours_e.get(ce)
    if e is None:
        flags['Not in our spell_fx.json (nothing plays)'].append(who)
        continue
    # animations
    for i, col in enumerate((3, 4, 5)):
        n = num(r, col)
        if n <= 0:
            continue
        head = anim_header[n + 2] if n + 2 < len(anim_header) else '?'
        clip = e['anims'][i] if i < len(e['anims']) else ''
        if not clip:
            flags['Casting animation column not mapped to a clip'].append(f'{who}: Anim{i + 1} = {n} ({head})')
            continue
        lacking = [f for f, cl in fig_clips.items() if clip not in cl]
        if lacking:
            flags['Casting clip missing on race figures'].append(f'{who}: {clip} ({head}) missing on {len(lacking)} figures, e.g. {", ".join(sorted(lacking)[:4])}')
    # effects
    for what, col in COLS.items():
        fid = num(r, col)
        if fid <= 0:
            continue
        if what in ('pulse', 'radius'):
            unused[f'{what.capitalize()} effect (spells.csv column {col}) - never played by SpellFx'].append(
                f'{who}: effect {fid} {speffects.get(str(fid), ["", "?"])[1].strip()}')
        if str(fid) not in speffects:
            flags['Effect id not in speffects.csv'].append(f'{who}: {what} {fid}')
            continue
        nif = nif_of(fid)
        if nif is None:
            flags['Effect not in our fx table (not drawn)'].append(f'{who}: {what} {fid} {speffects[str(fid)][1].strip()}')
            continue
        if nif not in checked_nifs:
            checked_nifs[nif] = gltf_ok(nif)
            p = G / nif.replace('res://', '')
            if p.exists():
                doc = json.loads(p.read_text(encoding='utf-8'))
                for m in doc.get('extras', {}).get('nif_materials', []):
                    if m.get('alpha') == 'add' and 'dark' in m.get('slots', {}):
                        mat_add_dark[nif].add(m['slots']['dark']['tex'])
                    if m.get('alpha') in ('mask', 'blend') and not m.get('unlit') and float(m.get('mat_light', 1)) < 0.3 \
                            and 'base' in m.get('slots', {}):
                        mat_dark_cut[nif].add(m['slots']['base']['tex'])
        if checked_nifs[nif]:
            flags['Effect model problem'].append(f'{who}: {what} {fid} {Path(nif).parent.name}: {checked_nifs[nif]}')
    # sounds
    ss = num(r, 14)
    if ss > 0:
        row = sounds['spells'].get(str(ss))
        if row is None:
            flags['Sound set not in our sound table'].append(f'{who}: set {ss}')
        else:
            for ev in ('gather', 'cast', 'travel', 'hit', 'resisted'):
                if row.get(ev) and not sound_file_ok(row[ev]):
                    flags['Sound does not resolve to a file'].append(f'{who}: set {ss} {ev} = {row[ev]}')
    # client columns we ignore
    for col, label in ((17, 'Projectile Lag'), (18, 'Play Anims'), (19, 'CasterFX Focus'), (20, 'Remove Effect on Cast')):
        if col < len(r) and r[col].strip() not in ('', '0'):
            unused[f'{label} (spells.csv column {col}) - not read by our player'].append(f'{who}: {r[col].strip()}')
    if not any(num(r, c) for c in (3, 4, 5)) and (num(r, 8) or num(r, 9)):
        unused['No casting animation but a caster effect (shown only on non-figures since 2026-10-14)'].append(who)

lines = ['# Spell FX audit (old client tables vs 0.36c)', '',
         f'Generated by pipeline/audit_spell_fx.py. {len(used)} client effects used by the server\'s spells were checked. '
         'Nothing was changed - these are flags to look at. "e.g." lists are cut to the first entries.', '']


def section(title, items, cap=40):
    lines.append(f'## {title} ({len(items)})')
    for it in sorted(set(items))[:cap]:
        lines.append(f'- {it}')
    if len(set(items)) > cap:
        lines.append(f'- ... {len(set(items)) - cap} more')
    lines.append('')


for k in sorted(flags):
    section(k, flags[k])
lines.append('# Client columns 0.36c does not play')
lines.append('')
for k in sorted(unused):
    section(k, unused[k], 25)
lines.append('# Material patterns (seen 2026-10-14 on Bark Skin / Strength of the Oak)')
lines.append('')
section('Additive layer with a mask in the dark slot (drawn flat / to the full shape, not the soft mask) - effect models',
        [f'{Path(n).parent.name}: {", ".join(sorted(t))}' for n, t in mat_add_dark.items()], 80)
section('Dark lit cut-out / blend layers (mat_light < 0.3: can look near black in our lighting) - effect models',
        [f'{Path(n).parent.name}: {", ".join(sorted(t))}' for n, t in mat_dark_cut.items()], 80)
OUT.write_text('\n'.join(lines), encoding='utf-8')
print(OUT, {k: len(v) for k, v in flags.items()}, {k: len(v) for k, v in unused.items()},
      len(mat_add_dark), len(mat_dark_cut))
