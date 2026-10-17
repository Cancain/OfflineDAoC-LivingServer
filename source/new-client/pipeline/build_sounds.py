"""DAoC client sound data for MMOEngine (client sounds only: nothing is replaced or substituted).

    python build_sounds.py 200 209 222        # zone audio for these zones + the sound files they use

The client's sound system is data-driven (app/sounds/cc_*.csv, authored by Mythic):
  cc_sounds.csv   ,ID#, sound ID (name), filename, rate, vol, pan, offset, r1, r2, ..., polygroup
                  values may be ranges ("0.8-1.0") or "*" (use the s_default row); pan "C", ".9L-.9R", ".5R"
  cc_mp3s.csv     ,ID#, sound ID, filename, notes      (zones.dat entry_music= points here, e.g. 5 = hibentry.mp3)
  cc_groups / cc_queues / cc_loops / cc_creatures / cc_doors / cc_weapons / cc_spells / cc_interface: later
Zone audio: zones/zoneNNN/sounds.dat, [SoundRegionNN] sections:
  header  fade_on_mp3, fade_time, random_sound_spacing, zone_wide_sounds (1 = ignore shapes), sound_type
          (1 ambient sfx / 2 ambient music / 3 sound effect)
  SoundNN = Type (1 random one-shot, 2 loop), Sound (cc_sounds ID), Period (s), Chance (%), Volume (0-100),
            Start, End (game time HHMM, may wrap past midnight), Weather (0 any, 1 clear only, 2 rain only)
  ShapeNN = 0, left, top, right, bottom (rect) | 1, x, y, radius (circle), zone units
Writes godot/content/sounds/sounds.json (id -> file + playback ranges) and files/<file> (copied as-is), and returns
the zone audio block that build_zone.py stores in zone.json.
"""
import csv, io, json, re, shutil, struct, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk

SOUND_DIR = CLIENT / 'sounds'

# sounds.dat ids with no cc_sounds row (silent in the real client), mapped to client rows by NAME.
# OWNER-APPROVED ONLY: add an entry here only when the owner OKs it (rule: no substitutes without the OK).
# Value: row name, or (row name, volume scale) when the owner asks for a different level.
OWNER_MAPPED = {
    176: ('s_Lake_Loop', 0.04),                            # Lough Derg "lakes" regions -> lakeloop.wav (owner 2026-10-09);
                                                           # owner: "way too loud", "omega loud" -> x0.04 (under the 0.09 bed); in-game volume options come later
    526: 's_Horse_Hooves(d)01', 527: 's_Horse_Hooves(d)02',  # Tir na Nog distant horse hooves (owner 2026-10-09)
    528: 's_Horse_Hooves(d)03', 529: 's_Horse_Hooves(d)04',
    530: 's_Horse_Vocal(d)_01', 531: 's_Horse_Vocal(d)_02',  # Tir na Nog distant horse whinny (owner 2026-10-09)
    532: 's_Horse_Vocal(d)_03', 533: 's_Horse_Vocal(d)_04',
}
OUT = ROOT / 'godot/content/sounds'


def _rows(name):
    return list(csv.reader(io.StringIO((SOUND_DIR / name).read_text(encoding='latin1'))))


def _range(v, default):
    v = (v or '').strip()
    if v in ('', '*'):
        return default
    parts = v.split('-')
    try:
        nums = [float(p) for p in parts if p != '']
    except ValueError:
        return default
    return [nums[0], nums[-1]] if nums else default


def _pan(v, default):
    v = (v or '').strip().upper()
    if v in ('', '*'):
        return default

    def one(t):
        t = t.strip()
        if t in ('C', ''):
            return 0.0
        side = -1.0 if t.endswith('L') else 1.0
        try:
            return side * float(t[:-1] or 1)
        except ValueError:
            return 0.0
    parts = v.split('-')
    vals = [one(p) for p in parts if p.strip()]
    return [min(vals), max(vals)] if vals else default


def sound_table():
    """{id: {...}} for every cc_sounds.csv row."""
    rows = _rows('cc_sounds.csv')
    return sound_tables()[0]


def sound_tables():
    """({id: row}, {name: row}) from cc_sounds.csv. Rows retired to ID 0 are only reachable by name."""
    rows = _rows('cc_sounds.csv')
    default = {'rate': [1.0, 1.0], 'vol': [1.0, 1.0], 'pan': [0.0, 0.0], 'offset': [0.0, 0.0], 'r1': [0.0, 0.0],
               'r2': [1000.0, 1000.0]}
    col = lambda r, i: r[i] if len(r) > i else ''
    for r in rows:
        if len(r) > 3 and r[0].strip() == '#' and r[2].strip() == 's_default':
            default = {'rate': _range(r[4], [1.0, 1.0]), 'vol': _range(r[5], [1.0, 1.0]), 'pan': _pan(r[6], [0.0, 0.0]),
                       'offset': _range(r[7], [0.0, 0.0]), 'r1': _range(r[8], [0.0, 0.0]),
                       'r2': _range(r[9], [1000.0, 1000.0])}
    by_id, by_name = {}, {}
    for r in rows:
        if len(r) > 3 and r[0].strip() == '' and r[1].strip().isdigit() and r[3].strip():
            row = {'id': int(r[1]), 'name': r[2].strip(), 'file': r[3].strip(),
                   'rate': _range(col(r, 4), default['rate']), 'vol': _range(col(r, 5), default['vol']),
                   'pan': _pan(col(r, 6), default['pan']), 'offset_ms': _range(col(r, 7), default['offset']),
                   'range_units': [_range(col(r, 8), default['r1'])[0], _range(col(r, 9), default['r2'])[-1]],
                   'polygroup': col(r, 12).strip() if col(r, 12).strip() not in ('', '*') else ''}
            if row['id']:
                by_id[row['id']] = row
            by_name.setdefault(row['name'].lower(), row)
    return by_id, by_name


def _members(text):
    """'s_Step_OnDirtSmall01, *02, *03' -> full names: '*NN' swaps the first member's last len(NN) characters."""
    out = []
    for m in (x.strip() for x in text.split(',')):
        if not m:
            continue
        if m.startswith('*') and out:
            tail = m[1:]
            m = out[0][:len(out[0]) - len(tail)] + tail
        out.append(m)
    return out


def structures():
    """cc_groups (pick one member at random), cc_queues (members in order, interval ms), cc_loops (start/body/stop)."""
    groups, queues, loops = {}, {}, {}
    for r in _rows('cc_groups.csv'):
        if len(r) > 2 and r[0].strip() == '' and r[1].strip().startswith('g_'):
            groups[r[1].strip().lower()] = _members(r[2])
    for r in _rows('cc_queues.csv'):
        if len(r) > 3 and r[0].strip() == '' and r[1].strip().startswith('q_'):
            queues[r[1].strip().lower()] = {'members': _members(r[2]), 'interval_ms': _range(r[3], [0.0, 0.0])}
    for r in _rows('cc_loops.csv'):
        if len(r) > 5 and r[0].strip() == '' and r[1].strip().startswith('l_'):
            loops[r[1].strip().lower()] = {'start': r[2].strip(), 'body': r[3].strip(), 'stop': r[4].strip(),
                                           'dur': r[5].strip()}
    return groups, queues, loops


CREATURE_COLUMNS = ['attack', 'pain_light', 'pain_medium', 'pain_heavy', 'die', 'evade', 'splat', 'move_dirt',
                    'move_water', 'swim_surface', 'swim_underwater', 'surface', 'fly', 'idle']


def creature_sets():
    """cc_creatures.csv: sound set id -> {column: structure name}; monsters.csv 'Sound Set' links a model to one."""
    out = {}
    for r in _rows('cc_creatures.csv'):
        if r and r[0].strip().isdigit() and len(r) > 15:
            out[int(r[0])] = {'name': r[1].strip(),
                              **{c: r[2 + i].strip() for i, c in enumerate(CREATURE_COLUMNS) if r[2 + i].strip()}}
    return out


def model_sound_sets():
    """figure NIF name (monnifs.csv) -> sound set (monsters.csv column 'Sound Set'), first monster using it."""
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    nifs = {r[0].strip(): r[2].strip().lower() for r in csv.reader(io.StringIO(g['monnifs.csv'].decode('latin1')))
            if len(r) > 2 and r[0].strip().isdigit()}
    out = {}
    for r in csv.reader(io.StringIO(g['monsters.csv'].decode('latin1'))):
        if len(r) > 15 and r[0].strip().isdigit() and r[15].strip().isdigit() and int(r[15]) > 0:
            nif = nifs.get(r[2].strip())
            if nif:
                out.setdefault(nif, int(r[15]))
    return out


def resolve(name, by_name, groups, queues, loops, seen=None):
    """Every s_ row a structure can play (groups/queues/loops nest)."""
    seen = set() if seen is None else seen
    key = name.strip().lower()
    if not key or key in seen:
        return []
    seen.add(key)
    if key.startswith('s_'):
        return [by_name[key]] if key in by_name else []
    if key in by_name and key not in groups and key not in queues and key not in loops:
        return [by_name[key]]                              # a cc_sounds row named without the s_ prefix (spell_eldgath)
    members = groups.get(key) or queues.get(key, {}).get('members') or \
        [v for k, v in loops.get(key, {}).items() if k in ('start', 'body', 'stop') and v]
    out = []
    for m in members:
        out += resolve(m, by_name, groups, queues, loops, seen)
    return out


def polygroups():
    """cc_sounds.csv POLYGROUPS block: name -> simultaneous-voice limit (ambient_sfx = 6)."""
    out, inside = {}, False
    for r in _rows('cc_sounds.csv'):
        if r and r[0].strip() == '!':
            inside = len(r) > 1 and r[1].strip() == 'POLYGROUPS'
        elif inside and r and r[0].strip() == '#' and len(r) > 5 and r[2].strip():
            out[r[2].strip()] = {'limit': int(float(r[4] or 0)), 'cutoff': int(float(r[5] or 0))}
    return out


def mp3_table():
    out = {}
    for r in _rows('cc_mp3s.csv'):
        if len(r) > 3 and r[1].strip().isdigit():
            out[int(r[1])] = {'name': r[2].strip(), 'file': r[3].strip()}
    return out


def parse_sounds_dat(text):
    regions, cur = [], None
    for raw in text.splitlines():
        line, _, note = raw.partition(';')
        line, note = line.strip(), note.strip()
        if not line:
            continue
        m = re.match(r'^\[(.+)\]$', line)
        if m:
            cur = {'section': m.group(1), 'name': '', 'zone_wide': True, 'sounds': [], 'shapes': [], 'fade_time': 5,
                   'random_sound_spacing': 5, 'sound_type': 1}
            regions.append(cur)
            continue
        if cur is None or '=' not in line:
            continue
        k, v = (s.strip() for s in line.split('=', 1))
        kl = k.lower()
        if kl == 'name':
            cur['name'] = v
        elif kl == 'zone_wide_sounds':
            cur['zone_wide'] = v.strip() == '1'
        elif kl == 'fade_on_mp3':
            cur['fade_on_mp3'] = v.strip() == '1'
        elif kl in ('fade_time', 'random_sound_spacing', 'sound_type'):
            cur[kl] = int(float(v or 0))
        elif kl.startswith('sound') and kl[5:].isdigit():
            f = [x.strip() for x in v.split(',')]
            if len(f) >= 8:
                # version 1 rows give a cc_sounds id; version 2 rows (162 zones, owner 2026-10-10: Muspelheim's lava was
                # silent - every name read as id 0) name a structure (s_ row, g_ group, q_ queue) and may give the
                # spacing as a range "20-60" seconds and a 9th field: 1 above water, 2 underwater
                ref = f[1]
                named = not re.match(r'^\s*\d+\s*$', ref)
                lo, _, hi = f[2].partition('-')
                snd = {'type': _atoi(f[0]), 'id': 0 if named else _atoi(ref), 'period': _atof(lo),
                       'chance': _atof(f[3]), 'volume': _atof(f[4]), 'start': _atoi(f[5]), 'end': _atoi(f[6]),
                       'weather': _atoi(f[7]), 'note': note}
                if hi.strip():
                    snd['period_max'] = _atof(hi)
                if named:
                    snd['name'] = ref.lower()
                if len(f) >= 9 and f[8].strip():
                    snd['env'] = _atoi(f[8])                  # 2 = underwater only (1.65: no diving - never)
                cur['sounds'].append(snd)
        elif kl.startswith('shape') and kl[5:].isdigit():
            f = [float(x) for x in v.split(',') if x.strip()]
            if f and f[0] == 1 and len(f) >= 4:
                cur['shapes'].append({'circle': [f[1], f[2], f[3]]})
            elif f and f[0] == 0 and len(f) >= 5:
                cur['shapes'].append({'rect': f[1:5]})
    return [r for r in regions if r['sounds']]


IMA_STEPS = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
             107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
             876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
             4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
             22385, 24623, 27086, 29794, 32767]
IMA_INDEX = [-1, -1, -1, -1, 2, 4, 6, 8]


def _chunks(raw):
    i, out = 12, {}
    while i + 8 <= len(raw):
        cid, size = raw[i:i + 4], struct.unpack('<I', raw[i + 4:i + 8])[0]
        out.setdefault(cid, raw[i + 8:i + 8 + size])
        i += 8 + size + (size & 1)
    return out


def _ima_block(block, channels):
    """One IMA ADPCM block (Microsoft/IMA layout) -> interleaved int16 samples."""
    pred, index = [], []
    for c in range(channels):
        p, ix = struct.unpack('<hB', block[c * 4:c * 4 + 3])
        pred.append(p)
        index.append(min(ix, 88))
    chans = [[p] for p in pred]
    data = block[4 * channels:]
    for g in range(0, len(data) - 4 * channels + 1, 4 * channels):   # 4 bytes (8 nibbles) per channel in turn
        for c in range(channels):
            for byte in data[g + c * 4:g + c * 4 + 4]:
                for nib in (byte & 15, byte >> 4):
                    step = IMA_STEPS[index[c]]
                    diff = step >> 3
                    if nib & 1: diff += step >> 2
                    if nib & 2: diff += step >> 1
                    if nib & 4: diff += step
                    pred[c] = max(-32768, min(32767, pred[c] - diff if nib & 8 else pred[c] + diff))
                    index[c] = max(0, min(88, index[c] + IMA_INDEX[nib & 7]))
                    chans[c].append(pred[c])
    n = min(len(ch) for ch in chans)
    return [chans[c][i] for i in range(n) for c in range(channels)]


def _write_wav(src, dst):
    """Copy a client WAV as-is; IMA ADPCM (format 17, which Godot can't load) is decoded losslessly to 16-bit PCM."""
    raw = src.read_bytes()
    ch = _chunks(raw)
    fmt = ch.get(b'fmt ', b'')
    if len(fmt) < 16 or struct.unpack('<H', fmt[:2])[0] != 17:
        shutil.copy2(src, dst)
        return
    _, channels, rate, _, align, _ = struct.unpack('<HHIIHH', fmt[:16])
    data, samples = ch[b'data'], []
    for b in range(0, len(data) - 4 * channels + 1, align):
        samples += _ima_block(data[b:b + align], channels)
    fact = ch.get(b'fact')
    if fact:                                              # true sample count (the last block is padded)
        samples = samples[:struct.unpack('<I', fact[:4])[0] * channels]
    pcm = struct.pack(f'<{len(samples)}h', *samples)
    hdr = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF', 36 + len(pcm), b'WAVE', b'fmt ', 16, 1, channels, rate,
                      rate * channels * 2, channels * 2, 16, b'data', len(pcm))
    dst.write_bytes(hdr + pcm)


def _is_adpcm(path):
    fmt = _chunks(path.read_bytes()[:4096]).get(b'fmt ', b'')
    return len(fmt) >= 2 and struct.unpack('<H', fmt[:2])[0] == 17


def _find(name):
    low = name.lower()
    for p in SOUND_DIR.iterdir():
        if p.name.lower() == low:
            return p
    return None


def zone_audio(zone_id, used_ids, used_mp3s, used_names=None):
    used_names = set() if used_names is None else used_names
    """Audio block for one zone; records the sound ids / mp3s it needs."""
    path = CLIENT / f'zones/zone{zone_id:03d}/sounds.dat'
    if not path.exists():                                  # the Albion epic dungeons ship in frontiers/zones
        path = CLIENT / f'frontiers/zones/zone{zone_id:03d}/sounds.dat'
    regions = parse_sounds_dat(path.read_text(encoding='latin1')) if path.exists() else []
    for reg in regions:
        for s in reg['sounds']:
            if s.get('name'):
                used_names.add(s['name'])
            else:
                used_ids.add(s['id'])
    zones = read_mpk(str(CLIENT / 'zones/zones.mpk'))['zones.dat'].decode('latin1')
    m = re.search(rf'\[zone{zone_id:03d}\](.*?)(?=\n\[|\Z)', zones, re.S | re.I)
    music = None
    if m:
        em = re.search(r'entry_music\s*=\s*(\d+)', m.group(1))
        if em:
            music = int(em.group(1))
            used_mp3s.add(music)
    return {'zone': zone_id, 'regions': regions, 'entry_music_id': music}


WEAPON_COLUMNS = {'activate': 4, 'use': 7, 'style_use': 8, 'hit_light': 11, 'hit_medium': 12, 'style_hit': 13,
                  'parried': 18, 'blocked': 19, 'deactivate': 24}   # cc_weapons.csv columns (its 'name' header row)


def weapon_sets():
    """cc_weapons.csv: weapon sound set (objects.csv 'Sound Set'; 19 = weaponless) -> {event: structure name}."""
    out = {}
    for r in _rows('cc_weapons.csv'):
        if r and r[0].strip().isdigit():
            out[int(r[0])] = {'name': r[1].strip(),
                              **{k: r[i].strip() for k, i in WEAPON_COLUMNS.items() if i < len(r) and r[i].strip()}}
    return out


SPELL_COLUMNS = {'gather': 2, 'shape': 3, 'cast': 4, 'travel': 5, 'hit': 6, 'miss': 7, 'resisted': 8, 'fizzle': 9}


def spell_sets():
    """cc_spells.csv: spell sound set (spells.csv 'Sound Set') -> {event: structure name} (gather while casting, cast
    when it goes off, travel for a bolt, hit / miss / resisted on the target, fizzle when interrupted)."""
    out = {}
    for r in _rows('cc_spells.csv'):
        if r and r[0].strip().isdigit():
            out[int(r[0])] = {'name': r[1].strip(),
                              **{k: r[i].strip() for k, i in SPELL_COLUMNS.items() if i < len(r) and r[i].strip()}}
    return out


def export(used_ids, used_mp3s, extra_ids=(), creature_set_ids=(), weapon_set_ids=(), spell_set_ids=(), structure_names=()):
    """Copy the used client sound files and write sounds.json (merged with what earlier builds exported)."""
    table, by_name = sound_tables()
    mp3s = mp3_table()
    files_dir = OUT / 'files'
    files_dir.mkdir(parents=True, exist_ok=True)
    (ROOT / 'godot/content/.gdignore').touch()
    index_path = OUT / 'sounds.json'
    index = json.loads(index_path.read_text(encoding='utf-8')) if index_path.exists() else {'sounds': {}, 'mp3': {}}
    missing = []
    for sid in sorted(set(used_ids) | set(extra_ids)):
        row = table.get(sid)
        if row is None and sid in OWNER_MAPPED:
            name, scale = OWNER_MAPPED[sid] if isinstance(OWNER_MAPPED[sid], tuple) else (OWNER_MAPPED[sid], 1.0)
            row = by_name.get(name.lower())
            row = dict(row, owner_mapped_from=sid, vol=[v * scale for v in row['vol']]) if row else None
        src = _find(row['file']) if row else None
        if src is None:
            missing.append(sid)
            continue
        dst = files_dir / src.name.lower()
        if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime or _is_adpcm(dst):
            _write_wav(src, dst)
        index['sounds'][str(sid)] = dict(row, file=f'files/{dst.name}')
    for mid in sorted(used_mp3s):
        row = mp3s.get(mid)
        src = _find(row['file']) if row else None
        if src is None:
            missing.append(f'mp3 {mid}')
            continue
        dst = files_dir / src.name.lower()
        if not dst.exists():
            shutil.copy2(src, dst)
        index['mp3'][str(mid)] = dict(row, file=f'files/{dst.name}')
    index['polygroups'] = polygroups()
    # creature sound sets (footsteps, swim strokes, vocals...) for the models in use, with every structure they name
    groups, queues, loops = structures()
    sets = creature_sets()
    for k in ('creatures', 'named', 'groups', 'queues'):
        index.setdefault(k, {})
    index['model_sound_sets'] = model_sound_sets()
    index.setdefault('weapons', {})
    wsets = weapon_sets()
    todo = []
    for sid in creature_set_ids:
        cs = sets.get(int(sid))
        if not cs:
            missing.append(f'creature set {sid}')
            continue
        index['creatures'][str(sid)] = cs
        todo.append(cs)
    for sid in weapon_set_ids:
        ws = wsets.get(int(sid))
        if not ws:
            missing.append(f'weapon set {sid}')
            continue
        index['weapons'][str(sid)] = ws
        todo.append(ws)
    index.setdefault('spells', {})
    ssets = spell_sets()
    for sid in spell_set_ids:
        ss = ssets.get(int(sid))
        if not ss:
            missing.append(f'spell set {sid}')
            continue
        index['spells'][str(sid)] = ss
        todo.append(ss)
    if structure_names:                                     # zone sounds named in version 2 sounds.dat rows
        todo.append({'name': 'zone structures', **{f'z{i}': n for i, n in enumerate(sorted(structure_names))}})
    for cs in todo:
        for col_name, struct_name in cs.items():
            if col_name == 'name':
                continue
            stack = [struct_name.lower()]
            while stack:
                k = stack.pop()
                if k in groups and k not in index['groups']:
                    index['groups'][k] = groups[k]
                    stack += [m.lower() for m in groups[k]]
                elif k in queues and k not in index['queues']:
                    index['queues'][k] = queues[k]
                    stack += [m.lower() for m in queues[k]['members']]
            for row in resolve(struct_name, by_name, groups, queues, loops):
                src = _find(row['file'])
                if src is None:
                    missing.append(row['name'])
                    continue
                dst = files_dir / src.name.lower()
                if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime or _is_adpcm(dst):
                    _write_wav(src, dst)
                index['named'][row['name'].lower()] = dict(row, file=f'files/{dst.name}')
    index_path.write_text(json.dumps(index, indent=1), encoding='utf-8')
    return missing


def build(zone_id):
    """content/zones/zoneNNN/audio.json + the client files it plays. References the client itself can't play
    (no cc_sounds row, e.g. Lough Derg's lake loop 176) stay silent and are listed under 'dead_refs' for the owner."""
    used, mp3, names = set(), set(), set()
    audio = zone_audio(zone_id, used, mp3, names)
    missing = set(export(used, mp3, structure_names=names))
    by_id, by_name = sound_tables()
    groups, queues, loops = structures()
    for n in names:                                         # a name nothing in the client's tables can play
        if not resolve(n, by_name, groups, queues, loops):
            missing.add(n)
    dead = {}
    for reg in audio['regions']:
        for s in reg['sounds']:
            key = s.get('name') or s['id']
            if key in missing:
                dead.setdefault(str(key), {'regions': set(), 'notes': set()})
                dead[str(key)]['regions'].add(reg['name'] or reg['section'])
                if s['note']:
                    dead[str(key)]['notes'].add(s['note'])
    audio['dead_refs'] = {k: {'regions': sorted(v['regions']), 'notes': sorted(v['notes'])} for k, v in dead.items()}
    out = ROOT / f'godot/content/zones/zone{zone_id:03d}'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'audio.json').write_text(json.dumps(audio, indent=1), encoding='utf-8')
    print(f'zone {zone_id}: {len(audio["regions"])} sound regions, {len(used)} sounds, entry music {audio["entry_music_id"]}, '
          f'{len(names)} named structures, silent in the client too: {sorted(dead, key=str)}')
    return audio


def _atoi(x):
    m = re.match(r'\s*[-+]?\d+', x)
    return int(m.group(0)) if m else 0


def _atof(x):
    m = re.match(r'\s*[-+]?(\d+\.?\d*|\.\d+)', x)
    return float(m.group(0)) if m else 0.0


def main():
    """python build_sounds.py 200 209 222 [--creatures=8,11]   (8 / 11 = Celt male / female, monsters.csv Sound Set)"""
    zones = [int(a) for a in sys.argv[1:] if not a.startswith('--')]
    sets = [int(x) for a in sys.argv[1:] if a.startswith('--creatures=') for x in a.split('=', 1)[1].split(',')]
    for z in zones:
        build(z)
    if '--combat' in sys.argv:
        # every monster model's creature set + the player races' + every weapon's sound set (objects.csv col 21)
        mons = json.loads((ROOT / 'godot/content/monsters/monsters.json').read_text())
        sets += [int(m['sound_set']) for m in mons.values() if int(m.get('sound_set', 0)) > 0]
        races = ROOT / 'godot/content/characters/races'
        sets += [int(json.loads(f.read_text()).get('sound_set', 0)) for f in races.glob('*/figure.json')]
        g = read_mpk(str(CLIENT / 'gamedata.mpk'))
        objects = {r[0]: r for r in csv.reader(io.StringIO(g['objects.csv'].decode('latin1'))) if r and r[0].isdigit()}
        weapons = json.loads((ROOT / 'godot/content/weapons/weapons.json').read_text())['models']
        wsets = sorted({int(objects[m][21]) for m in weapons if m in objects and objects[m][21].strip().isdigit()} | {19})
        # every set of the weapon sheet (cc_weapons.csv): the server's NPCs and bots swing weapons this game never
        # converted (crossbows, whips, flails, the mauler's fists - owner 2026-10-13: no weapon sounds)
        wsets = sorted(set(wsets) | {int(r[0]) for r in _rows('cc_weapons.csv') if r and r[0].strip().isdigit()})
        print('combat sounds: missing', export(set(), set(), creature_set_ids=sorted(set(x for x in sets if x > 0)),
                                               weapon_set_ids=wsets))
    elif sets:
        print('creature sets: missing', export(set(), set(), creature_set_ids=sets))
    if '--doors' in sys.argv:
        # cc_doors.csv: the client plays a door's open / close sound from the "flag" byte the server sends with the
        # door's state (the cc_doors row). The old server gives every unflagged door above ground flag 1 (wooden,
        # metal-hinged door) - not in dungeons (zones.dat type 2) - so: flag 1 for every zone that isn't a dungeon.
        _, by_name = sound_tables()
        doors, ids = {}, []
        for r in _rows('cc_doors.csv'):
            if not r or not r[0].strip().isdigit():
                continue
            ent = {'name': r[1].strip(), 'notes': r[4].strip() if len(r) > 4 else ''}
            for k, col in (('open', 2), ('close', 3)):
                row = by_name.get(r[col].strip().lower()) if len(r) > col and r[col].strip() else None
                if row and int(row['id']) > 0:
                    ent[k] = int(row['id'])
                    ids.append(int(row['id']))
            doors[r[0].strip()] = ent
        print('door sounds: missing', export(set(), set(), extra_ids=ids))
        from build_zone import zone_section
        zone_flag = {}
        for d in (ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]'):
            zid = int(d.name[4:])
            t = re.search(r'^\s*type\s*=\s*(\d+)', zone_section(zid), re.M)
            zone_flag[str(zid)] = 0 if t and int(t.group(1)) == 2 else 1
        index = json.loads((OUT / 'sounds.json').read_text(encoding='utf-8'))
        index['doors'] = doors
        index['zone_door_flag'] = zone_flag
        (OUT / 'sounds.json').write_text(json.dumps(index, indent=1), encoding='utf-8')
    if '--events' in sys.argv:
        # the server's SoundEffect ids (packet 0xC9 - cc_sounds rows the client plays when told): the low event rows
        # (click, bells, QuestBegun 7, QuestCompleted 11, relic pick up / put down, tower collapse) and every id the
        # Claude version's server sends (grep SendSoundEffect: 163, 216-220 horns, 2452, 2467)
        ids = list(range(1, 21)) + [163, 216, 217, 218, 219, 220, 2452, 2467]
        print('event sounds: missing', export(set(), set(), extra_ids=ids))
    if '--spells' in sys.argv:
        # every spell sound set the built spells use (content/spells/spell_fx.json from build_spell_fx.py)
        fx = json.loads((ROOT / 'godot/content/spells/spell_fx.json').read_text(encoding='utf-8'))
        ids = sorted({int(e['sound_set']) for e in fx['effects'].values() if int(e.get('sound_set', 0)) > 0})
        print(len(ids), 'spell sound sets: missing', export(set(), set(), spell_set_ids=ids))


if __name__ == '__main__':
    main()
