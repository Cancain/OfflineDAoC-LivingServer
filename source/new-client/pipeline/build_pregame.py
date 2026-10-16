"""Character select / creation ("pregame") content from the client, for MMOEngine's realm screens.

    python build_pregame.py            # -> godot/content/pregame/

The client's pregame (app/pregame/):
  charScreen{Alb,Hib,Mid}.npk   the three realm backdrops: real 3D scenes (towers, trees, banners, sky dome, cloud /
                                snow particles), two-texture terrain blend, camera-facing grass and leaf cards
  settings.dat [fog]            per-realm fog: r, g, b, density
  pregame.mpk                   the screen art: character_selection / creation / customize / location frames
                                (1024x768, transparent where the scene shows), realm_selection, buttons, medallions,
                                breadcrumbs, dialog box, sliders, eye / hair / skin colour palettes, realm banners and
                                the starting-town pictures (magmell, domnann, cotswold, caergothwaite, aegirhamn,
                                mularnvillage, mid_teleport)
  pregame003.mpk / 002          later replacements of character_customize / hair_colors_palettes
  realmdesc.mpk realmdesc.txt   the realm descriptions
Not used: splash.mpk (OfflineDAoC 0.35 art, not period), *.max (3ds Max sources), trial.mpk (trial nag screens).
character_creation.tga carries "Class / Race Combination: https://planner.atlasfreeshard.com" painted into its top
bar by a private server; it is covered with the identical stone strip from character_selection.tga.
Palettes are copied exactly (no upscale: they are colour lookups); everything else gets x4plus at 2x (frames are
viewed full screen) or 4x (small buttons and medallions).
"""
import io, json, shutil, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from texture_index import TextureIndex
from build_zone import upscale_dir, save_if_changed
import nif_static

OUT = ROOT / 'godot/content/pregame'
REALMS = {'alb': 'Alb', 'mid': 'Mid', 'hib': 'Hib'}
FULL = {'character_selection', 'character_creation', 'character_customize', 'character_location', 'realm_selection',
        'aegirhamn', 'caergothwaite', 'cotswold', 'domnann', 'magmell', 'mularnvillage', 'mid_teleport'}
EXACT = {'eye_color_palettes', 'hair_colors_palettes', 'skin_color_palettes', 'color_picker_indicator'}


def main():
    pre = CLIENT / 'pregame'
    ui = OUT / 'ui'
    for d in (ui / 'original_full', ui / 'original_small', ui / 'exact'):
        d.mkdir(parents=True, exist_ok=True)
    (ROOT / 'godot/content/.gdignore').touch()
    art = dict(read_mpk(str(pre / 'pregame.mpk')))
    art.update(read_mpk(str(pre / 'pregame003.mpk')))       # the later character_customize
    art.update(read_mpk(str(pre / 'pregame002.mpk')))       # the later hair colour palettes
    images = {}
    for k, v in art.items():
        if k.lower().endswith(('.tga', '.dds', '.bmp')):
            images[k.rsplit('.', 1)[0].lower()] = Image.open(io.BytesIO(v)).convert('RGBA')
    sel, cre = images['character_selection'], images['character_creation']
    cre.paste(sel.crop((0, 0, 760, 46)), (0, 0))              # cover the private server's URL with the same stone
    for name in ('albion_button', 'hibernia_button', 'midgard_button'):
        images[name] = key_emblem(images[name])
    # the Albion sheet carries a bright white block under its name (rows 179+) that the brightness key keeps: its top
    # edge showed as a line under "Albion" when selected (owner 2026-10-09) - the name ends at row ~198, the block starts at 206
    alb = images['albion_button'].copy()
    px = alb.load()
    for y in range(200, alb.height):
        for x in range(alb.width):
            r, g, b_, _ = px[x, y]
            px[x, y] = (r, g, b_, 0)
    images['albion_button'] = alb
    for name, im in images.items():
        if name in EXACT:
            im.save(ui / 'exact' / f'{name}.png')
        else:
            save_if_changed(im, ui / ('original_full' if name in FULL else 'original_small') / f'{name}.png')
    # owner 2026-10-09: realm select fills a wide screen (no black bars) - the frame is stretched to 16:9 BEFORE the
    # x4plus pass, so the upscale works on the stretched pixels and nothing looks smeared
    save_if_changed(images['realm_selection'].resize((1366, 768), Image.LANCZOS), ui / 'original_full' / 'realm_selection_wide.png')
    upscale_dir(ui / 'original_full', ui / 'full', factor_after=2)
    upscale_dir(ui / 'original_small', ui / 'small', factor_after=4)
    text = read_mpk(str(pre / 'realmdesc.mpk'))['realmdesc.txt'].decode('latin1')
    desc, cur = {}, None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('[') and line.endswith(']'):
            cur = line[1:-1].lower()
            desc[cur] = ''
        elif cur and line:
            desc[cur] = (desc[cur] + ' ' + line).strip()
    fog = {}
    for line in (pre / 'settings.dat').read_text(encoding='latin1').splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            vals = [float(x) for x in v.split(',')]
            fog[k.strip()] = {'color': [c / 255.0 for c in vals[:3]], 'density': vals[3] if len(vals) > 3 else 0}
    # the three realm scenes
    idx = TextureIndex()
    scenes = {}
    for key, cap in REALMS.items():
        d = OUT / key
        (d / 'textures/original').mkdir(parents=True, exist_ok=True)
        raw = read_mpk(str(pre / f'charScreen{cap}.npk'))[f'charscreen{key}.nif']
        info = nif_static.convert(raw, str(d / 'scene.gltf'), 'textures/original')
        missing = []
        for t in sorted(info['textures']):
            doubled = t.endswith(('__d2', '__x2'))   # __x2: the raw detail map (detail_x2.py)
            img = idx.image(t[:-4] if doubled else t)
            if img is None:
                missing.append(t)
                continue
            if doubled and t.endswith('__d2'):
                import numpy as np
                rgb = np.asarray(img.convert('RGB'), dtype=np.float32) * 2.0
                img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
            save_if_changed(img, d / 'textures/original' / f'{t}.png')
        upscale_dir(d / 'textures/original', d / 'textures/x4plus', factor_after=2)
        scenes[key] = {'file': f'{key}/scene.gltf', 'triangles': info['triangles'], 'particles': info['particles'],
                       'aabb': info['aabb'], 'missing_textures': missing, 'warnings': info['warnings']}
        print(key, info['triangles'], 'triangles,', info['particles'], 'particle systems, missing', missing,
              'warnings', info['warnings'][:4])
    charman = charman_texts()
    for realm, cuts in LATER_RACES.items():                # owner 2026-10-09: no post-1.65 races in the texts
        for old, new in cuts:
            assert old in desc[realm], (realm, old)
            desc[realm] = desc[realm].replace(old, new)
    meta = {'realm_descriptions': desc, 'startup': startup_locations(), 'fog': fog, 'scenes': scenes, **charman,
            'start_locations': {'hib': ['magmell', 'domnann'], 'alb': ['cotswold', 'caergothwaite'],
                                'mid': ['mularnvillage', 'aegirhamn']}}
    (OUT / 'pregame.json').write_text(json.dumps(meta, indent=1), encoding='utf-8')
    print('ui art:', sorted(images))


# realmdesc.txt is the later client's: it names races that came after 1.65 (owner: remove them entirely)
LATER_RACES = {
    'albion': [('The small, mysterious Inconnu along with the bestial Half-Ogres add a dash of the exotic to the Realm.',
                'The small, mysterious Inconnu add a dash of the exotic to the Realm.')],
    'hibernia': [('  The malevolent Shar have an uneasy alliance with the other races of Hibernia, and bring an undercurrent '
                  'of evil to the emerald hills.', '')],
    'midgard': [('is home to six of the most diverse races', 'is home to five of the most diverse races'),
                ('lithe dexterous Kobolds, shadowy, mysterious Frostalfs, and the primitive', 'lithe dexterous Kobolds, and the primitive')],
}


def key_emblem(im):
    """The realm emblem buttons (two states side by side) are opaque, painted on a dark patch of their panel that
    doesn't line up with the panel art, so they showed as boxes. The emblem and its name are bright metal / text on
    that dark patch: keep them by brightness above the patch's own colour (taken from the image border)."""
    import numpy as np
    a = np.asarray(im.convert('RGBA')).astype(np.float32)
    rgb = a[..., :3]
    border = np.concatenate([rgb[:4].reshape(-1, 3), rgb[:, :4].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    diff = np.abs(rgb - bg).max(axis=2)
    alpha = np.clip((diff - 18.0) / 40.0, 0.0, 1.0) * 255.0
    out = a.copy()
    out[..., 3] = np.minimum(a[..., 3], alpha)
    return Image.fromarray(out.astype(np.uint8), 'RGBA')


# DOL / OpenDAoC race and class ids (the old server's StartupLocation table) for the 1.65 base classes
RACE_IDS = {'BRIT': 1, 'AVAL': 2, 'HIGH': 3, 'SARE': 4, 'NORS': 5, 'TROL': 6, 'DWAR': 7, 'KOBO': 8, 'CELT': 9,
            'FIRB': 10, 'ELF': 11, 'LURI': 12, 'INCO': 13, 'VALK': 14, 'SYLV': 15}
BASE_IDS = {'FIGH': 14, 'ELEM': 15, 'ACOL': 16, 'ROGU': 17, 'MAGE': 18, 'ARAW': 20, 'WARR': 35, 'MYST': 36,
            'SPIR': 37, 'NROG': 38, 'MAGI': 51, 'ARMS': 52, 'NATU': 53, 'STEA': 54, 'GROV': 57}


def startup_locations():
    """Where a new character starts: the old server's StartupLocation table (read only, MinVersion 0 = the classic
    rows), by race + base class, converted to zone + zone-local units with zones.dat (owner 2026-10-09: start towns
    by base class, as that table has them). {'CELT-ARMS': {zone, x, y, z, heading}}."""
    import re, sqlite3
    from build_zone import OLD_DB
    text = read_mpk(str(CLIENT / 'zones/zones.mpk'))['zones.dat'].decode('latin1')
    zones = []
    for m in re.finditer(r'\[zone(\d+)\](.*?)(?=\n\[|$)', text, re.S | re.I):
        sec = {k.strip().lower(): v.strip() for k, v in (l.split('=', 1) for l in m.group(2).splitlines() if '=' in l)}
        try:
            zones.append((int(m.group(1)), int(sec.get('region', -1)), int(sec.get('region_offset_x', 0)) * 8192,
                          int(sec.get('region_offset_y', 0)) * 8192, int(sec.get('width', 8)) * 8192,
                          int(sec.get('height', 8)) * 8192, sec.get('name', '')))
        except ValueError:
            continue
    if not OLD_DB.exists():
        return {}
    con = sqlite3.connect(f'file:{OLD_DB.as_posix()}?mode=ro', uri=True)
    rows = con.execute('select RaceID, ClassID, Region, XPos, YPos, ZPos, Heading from StartupLocation '
                       'where MinVersion = 0').fetchall()
    out = {}
    for race, rid in RACE_IDS.items():
        for base, cid in BASE_IDS.items():
            hit = next((r for r in rows if r[0] == rid and r[1] == cid), None)
            if hit is None:
                continue
            _, _, region, x, y, z, heading = hit
            zone = next((zz for zz in zones if zz[1] == region and zz[2] <= x < zz[2] + zz[4] and zz[3] <= y < zz[3] + zz[5]), None)
            if zone:
                out[f'{race}-{base}'] = {'zone': zone[0], 'zone_name': zone[6], 'x': x - zone[2], 'y': y - zone[3],
                                         'z': z, 'heading': heading}
    return out


NOT_165 = ('HALF', 'FROS', 'SHAR')        # Half Ogre, Frostalf, Shar: later races, not 1.65 Classic + SI


def _sections(text):
    """[KEY] blocks of a charman text file -> {KEY: [non-empty lines]}."""
    out, cur = {}, None
    for line in text.splitlines():
        if line.startswith('[') and line.rstrip().endswith(']'):
            cur = line.strip()[1:-1]
            out[cur] = []
        elif cur is not None and line.strip():
            out[cur].append(line.strip())
    return out


def charman_texts():
    """app/charman: the client's character-creation texts (1.65 creation = race + BASE class, specialise at level 5).
    summary.txt   [RACE-BASE] title + description for every valid race / base class pair (the valid pairs themselves)
    startlocs.txt [RACE-BASE-n] starting town name + description
    names.dat     [race-first/second/third] syllables for the RANDOM name button"""
    cm = CLIENT / 'charman'
    summ = _sections(read_mpk(str(cm / 'summary.mpk'))['summary.txt'].decode('latin1'))
    locs = _sections(read_mpk(str(cm / 'startlocs.mpk'))['startlocs.txt'].decode('latin1'))
    names = {}
    for k, v in _sections((cm / 'names.dat').read_bytes().decode('latin1')).items():
        names[k] = v
    keep = lambda k: k.split('-')[0] not in NOT_165
    classes = {}
    for k, v in summ.items():
        if not keep(k) or not v:
            continue
        title, body = (v[0], v[1:]) if len(v[0]) < 60 else ('', v)    # AVAL-ELEM has no title line
        off = title.strip(' .').lower() in ('n/a', 'not available', 'not supported')    # greyed out in the client
        classes[k] = {'title': '' if off else title, 'text': '\n\n'.join(body), 'available': not off}
    return {'classes': classes,
            'start_texts': {k: {'town': v[0], 'text': ' '.join(v[1:])} for k, v in locs.items() if keep(k) and v},
            'name_syllables': {k: v for k, v in names.items()
                               if not k.startswith(('halfogre', 'frostalf', 'shar', 'minotaur'))}}


if __name__ == '__main__':
    main()
