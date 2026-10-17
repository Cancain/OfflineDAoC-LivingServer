"""Spell visuals and sounds from the client's own tables (owner 2026-10-10: spell animations / effects / sounds).

The spell's client effect number (DB Spell.ClientEffect, sent by the server in SpellEffectAnimation) indexes
gamedata spells.csv:
   0 ID, 1 Name, 2 Icon, 3-5 Anim1-3 (the caster's start / mid / end casting animation: anims.csv column = n + 2, the
   same rule as styles.csv / canims.csv - 32-34 = 1H Circ (heals, buffs), 35-37 = 2H Wax, 47-49 = Crossed, 22-24 =
   Lute (Bard / Minstrel songs), 29-31 = Flute (cadences); an earlier n - 1 reading gave every heal a flute), 6 Effect1A / 7 Effect1B (on the caster while it
   gathers - usually the two hand glows), 8 Effect2, 9 Effect3 (on the caster when the spell goes off), 10 Projectile
   Effect (a bolt flying to the target), 11 Target Effect, 12 Buildup Effect, 13 Pulse Effect, 14 Sound Set
   (cc_spells.csv), 15 Radius Effect, 16 Resist Effect, 17 Projectile Lag, 18 Play Anims, 19 CasterFX Focus,
   20 Remove Effect on Cast.
An effect number indexes speffects.csv: ID, Name, NIF (spnifs.csv id -> the effect NIF in app/effects), Node (the
bone it sits on: Bip01 L Held / Bip01 R Held / targetchest / rootnode ...), Duration (ms), Rate (%), Angle, Scale.
Writes godot/content/spells/spell_fx.json:
   {"effects": {client effect: {name, anims: [start, mid, end clip], gather: [fx id...], cast_fx: [...], projectile,
                target, buildup, pulse, radius, resist, sound_set, lag_ms}},
    "fx": {fx id: {name, nif (gltf path), node, duration_s, rate, scale}}}
and converts every effect NIF it names (build_monsters.build_effect -> content/monsters/effects/<nif>/).

    python build_spell_fx.py [--no-upscale]"""
import csv, io, json, re, sys
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
import nif_character as nc
from build_races import cast_clip
from texture_index import TextureIndex
import build_monsters

OUT = ROOT / 'godot/content/spells/spell_fx.json'


def table(g, name):
    return {r[0].strip(): r for r in csv.reader(io.StringIO(g[name].decode('latin1'))) if r and r[0].strip().isdigit()}


def num(r, i):
    try:
        return int(float(r[i])) if i < len(r) and r[i].strip() else 0
    except ValueError:
        return 0


def main():
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    spells_csv, speffects, spnifs = table(g, 'spells.csv'), table(g, 'speffects.csv'), table(g, 'spnifs.csv')
    header, _figs, _files = nc.animation_tables()
    # every client effect the game's spells use: the classes' spells, monster spells, pet spells
    used = set()
    for path in ('classes/spells.json', 'spells/npc_spells.json'):
        p = ROOT / 'godot/content' / path
        if p.exists():
            for sp in json.loads(p.read_text(encoding='utf-8')).values():
                ce = int(sp.get('clienteffect') or 0)
                if ce:
                    used.add(ce)
    # 0.36c: every client effect the shared server's spells use (read only) - the Sluaghbinder's (Cairnhide 4569, the
    # raise spells 4625-4631 ...), the custom NPCs' and ROG procs (owner 2026-10-11: no Sluaghbinder effect showed)
    db = ROOT.parent / 'new class test - CLAUDE VERSION/runtime/data/opendaoc.sqlite3.db'
    if db.exists():
        import sqlite3
        con = sqlite3.connect(db.as_uri() + '?mode=ro', uri=True)
        used.update(int(ce) for (ce,) in con.execute('select distinct ClientEffect from Spell where ClientEffect > 0'))
    # and every other row: the server names any client effect it likes - boss scripts build their spells in code
    # (the dragons' breaths 5700-5703, Fornfrusonen's void handglows, Govannon's Infernal Slice) or play an effect by
    # its number, none of them in the Spell table; the client plays whatever row it is sent (owner 2026-10-13: the
    # Malmohus dragon's breath showed nothing)
    if '--used-only' not in sys.argv:
        used.update(int(k) for k in spells_csv)
    # the emotes' overlays (emotes.csv Spell column): Pray 8005, Level Up 8007, the realm binds 8006 / 8009 / 8010
    for r in csv.reader(io.StringIO(g['emotes.csv'].decode('latin1'))):
        if r and r[0].strip().isdigit() and len(r) > 3 and r[3].strip().isdigit() and int(r[3]) > 0:
            used.add(int(r[3]))
    effects, fx_used = {}, set()

    def anim_clip(n):
        col = n + 2
        return cast_clip(header[col]) if 0 <= col < len(header) and ('Start' in header[col] or 'Mid' in header[col]
               or 'End' in header[col] or re.search(r'(?i)lute|drum|flute', header[col])) else ''

    for ce in sorted(used):
        r = spells_csv.get(str(ce))
        if r is None:
            continue
        e = {'name': r[1].strip(), 'anims': [anim_clip(num(r, i)) for i in (3, 4, 5)],
             'gather': [x for x in (num(r, 6), num(r, 7)) if x], 'cast_fx': [x for x in (num(r, 8), num(r, 9)) if x],
             'projectile': num(r, 10), 'target': num(r, 11), 'buildup': num(r, 12), 'pulse': num(r, 13),
             'sound_set': num(r, 14), 'radius': num(r, 15), 'resist': num(r, 16), 'lag_ms': num(r, 17)}
        effects[str(ce)] = e
        fx_used.update(e['gather'] + e['cast_fx'] + [e[k] for k in ('projectile', 'target', 'buildup', 'pulse', 'radius', 'resist') if e[k]])
    idx = TextureIndex()
    effect_files = {p.name.lower(): p for p in (CLIENT / 'effects').iterdir()}
    fx, built, missing = {}, [], []
    for fid in sorted(fx_used):
        r = speffects.get(str(fid))
        if r is None:
            missing.append(f'speffect {fid}')
            continue
        nr = spnifs.get(str(num(r, 2)))
        base = nr[2].strip().lower() if nr else ''
        if not base or base == 'empty':
            continue
        if not build_monsters.build_effect(base, idx, effect_files):
            missing.append(base)
            continue
        built.append(base)
        fx[str(fid)] = {'name': r[1].strip(), 'nif': f'res://content/monsters/effects/{base}/model.gltf',
                        'node': r[3].strip(), 'duration_s': num(r, 4) / 1000.0, 'rate': (num(r, 5) or 100) / 100.0,
                        # the header is two rows: col 6 "Track Angle" (1 / 2: the effect turns to face the target - the
                        # hand burst becomes a ray), col 7 "Auto Scale" (1: scaled by the character it sits on, like
                        # moneffects' AutoScale: its size / 50 x its model's monsters.csv scale), col 8 "Spin Axis"
                        'track': num(r, 6), 'autoscale': num(r, 7) == 1, 'spin': num(r, 8)}
    # the release moment of a cast effect: when its hidden streak / flash first shows (NiVisController). The old
    # client starts the target effect then - owner's Gleam Ray clip 2026-10-10: the ray first, the pink puff after
    # it; the server (DirectDamageSpellHandler) deals the damage at the end of the cast without delay
    for f in fx.values():
        g = json.loads((ROOT / 'godot' / f['nif'].replace('res://', '')).read_text(encoding='utf-8'))
        rel = [next((k[0] for k in a.get('vis', []) if k[1]), None) for a in g.get('extras', {}).get('nif_node_anims', [])
               if not a.get('visible', True)]
        rel = [r for r in rel if r is not None]
        if rel:
            f['release_s'] = round(min(rel), 3)
    for e in effects.values():
        rel = [fx[str(i)].get('release_s', 0.0) for i in e['cast_fx'] if str(i) in fx]
        if rel and max(rel) > 0 and not e['projectile']:
            e['release_s'] = max(rel)
    if '--no-upscale' not in sys.argv:
        from build_zone import upscale_dir
        for base in sorted(set(built)):
            d = build_monsters.EFX / base
            upscale_dir(d / 'textures/original', d / 'textures/x4plus', factor_after=4)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({'effects': effects, 'fx': fx,
                               'source': 'client gamedata spells.csv / speffects.csv / spnifs.csv, sounds cc_spells.csv'},
                              indent=1), encoding='utf-8')
    print(len(effects), 'client effects,', len(fx), 'effect models,', len(set(built)), 'NIFs; missing', missing[:20])


if __name__ == '__main__':
    main()
