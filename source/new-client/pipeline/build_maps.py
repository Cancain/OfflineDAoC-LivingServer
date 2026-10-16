"""The client's own map system (owner 2026-10-09: "the actual map system from the old client ... with its clear maps and
the dropdown to find maps and follow location toggle"). Post-1.65 (the in-game map came with test 1.71d), asked for by
the owner. Reads the client's ui/maps folder (read only):
  z###.dds       the painted map of each zone (256 x 256, north up, the zone's full square)
  z###_NN.dds    an area map inside a zone (a town / a dungeon wing) - areas.dat gives its rectangle in zone units
  r###.dds       a region map (the realm overview); regions.dat places each zone's square on it in pixels
  regions.dat    [regionNNN] zone_width / zone_height (default 50), zoneK_number / _left / _top (/ _width / _height),
                 region_desc / zoneK_desc; the comment line above each section names it
  areas.dat      [zoneNNN] areaK_left / _top / _width / _height (/ _z / _depth) in zone units, _name, _desc
Only zones this project has built (godot/content/zones/zoneNNN) and the region maps that hold one are kept.
Writes godot/content/maps/{original,x4plus}/*.png (x4plus = Real-ESRGAN x4plus 4x, as every texture) and
godot/content/maps/maps.json.

    python build_maps.py [--no-upscale]"""
import json, re, sys
from pathlib import Path
from PIL import Image
from assets_pipeline import ROOT, CLIENT
from build_zone import zone_name, zone_section

SRC = CLIENT / 'ui/maps'
OUT = ROOT / 'godot/content/maps'


def sections(path):
    """INI-ish file -> [(section, {key: value}, comment line above it)]."""
    out, cur, last_comment = [], None, ''
    for raw in path.read_text(encoding='latin-1').splitlines():
        line = raw.strip()
        if line.startswith(';'):
            txt = line.lstrip(';').strip()
            if txt and '=' not in txt and not txt.startswith('['):
                last_comment = txt
            continue
        m = re.match(r'^\[(\w+)\]', line)
        if m:
            cur = (m.group(1).lower(), {}, last_comment)
            out.append(cur)
            continue
        if cur is not None and '=' in line:
            k, v = line.split('=', 1)
            v = v.strip()
            if re.match(r'^-?\d+\s*;', v):              # "116;" - a stray trailing comment mark on numbers
                v = v.split(';')[0].strip()
            cur[1][k.strip().lower()] = v
    return out


def main():
    built = sorted(int(p.name[4:]) for p in (ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]') if (p / 'zone.json').exists())
    files = {p.name.lower(): p for p in SRC.iterdir()}
    (OUT / 'original').mkdir(parents=True, exist_ok=True)
    zones, regions = {}, {}
    for z in built:
        f = files.get(f'z{z:03d}.dds')
        sec = dict(l.split('=', 1) for l in zone_section(z).splitlines() if '=' in l)
        # zones.dat region (1 / 51 Albion + SI, 100 / 151 Midgard + SI, 200 / 181 Hibernia + SI ...) and type
        # (0 open world, 1 city, 2 dungeon): the map window lists your realm's open world + capital only
        zones[z] = {'name': zone_name(z) or f'Zone {z}', 'map': f'z{z:03d}.png' if f else '', 'areas': [], 'region_map': 0,
                    'desc': '', 'region': int(sec.get('region', -1)), 'type': int(sec.get('type', 0) or 0)}
    # area maps (towns / dungeon wings)
    for sec, kv, _ in sections(SRC / 'areas.dat'):
        m = re.match(r'zone(\d+)', sec)
        if not m or int(m.group(1)) not in zones:
            continue
        z = int(m.group(1))
        for k in range(int(kv.get('area_count', 0) or 0)):
            f = files.get(f'z{z:03d}_{k:02d}.dds')
            if not f or f'area{k}_left' not in kv:
                continue
            a = {'map': f'z{z:03d}_{k:02d}.png', 'name': kv.get(f'area{k}_name', ''), 'desc': kv.get(f'area{k}_desc', ''),
                 'rect': [int(kv[f'area{k}_left']), int(kv[f'area{k}_top']), int(kv[f'area{k}_width']), int(kv[f'area{k}_height'])]}
            if f'area{k}_z' in kv:
                a['z'] = int(kv[f'area{k}_z'])
            if f'area{k}_depth' in kv:
                a['depth'] = int(kv[f'area{k}_depth'])
            zones[z]['areas'].append(a)
    # region maps
    for sec, kv, label in sections(SRC / 'regions.dat'):
        m = re.match(r'region(\d+)', sec)
        if not m:
            continue
        r = int(m.group(1))
        w0, h0 = int(kv.get('zone_width', 50) or 50), int(kv.get('zone_height', 50) or 50)
        placed = []
        for k in range(int(kv.get('zone_count', 0) or 0)):
            if f'zone{k}_number' not in kv:
                continue
            z = int(kv[f'zone{k}_number'])
            placed.append({'zone': z, 'left': int(kv.get(f'zone{k}_left', 0) or 0), 'top': int(kv.get(f'zone{k}_top', 0) or 0),
                           'width': int(kv.get(f'zone{k}_width', w0) or w0), 'height': int(kv.get(f'zone{k}_height', h0) or h0)})
            if z in zones and kv.get(f'zone{k}_desc'):
                zones[z]['desc'] = kv[f'zone{k}_desc']
            # the capitals' and dungeons' own regions give their map's square in zone UNITS (game.dll's map: a spot
            # minus zoneK_offsetx / _offsety, over zoneK_width / _height - then an area's rect inside that): the
            # zone map shows that square, not the whole zone (owner 2026-10-14: Jordheim's map was way off - the
            # NPCs measured onto its painted streets with exactly these numbers)
            if z in zones and f'zone{k}_offsetx' in kv:
                ow = int(kv.get(f'zone{k}_width', 65536) or 65536)
                zones[z]['map_rect'] = [int(kv[f'zone{k}_offsetx']), int(kv.get(f'zone{k}_offsety', 0) or 0), ow,
                                        int(kv.get(f'zone{k}_height', ow) or ow)]
        f = files.get(f'r{r:03d}.dds')
        # the capital cities' "region" pictures (r010 Camelot, r101 Jordheim, r201 Tir na Nog) are unfinished raw
        # renders in the client, not maps - left out (the city's own zone map is the real one)
        if not f or r in (10, 101, 201) or not any(p['zone'] in zones for p in placed):
            continue
        regions[r] = {'name': label or f'Region {r}', 'map': f'r{r:03d}.png', 'desc': kv.get('region_desc', ''),
                      'zones': [p for p in placed if p['zone'] in zones]}
        for p in regions[r]['zones']:
            zones[p['zone']]['region_map'] = zones[p['zone']]['region_map'] or r
    # pictures
    names = [z['map'] for z in zones.values() if z['map']] + [a['map'] for z in zones.values() for a in z['areas']] + \
            [r['map'] for r in regions.values()]
    # the client's pictures as they are (client/), then with the period fixes (original/, map_edits.py), and the
    # list of what was taken out (content/maps/period_fixes.json)
    import numpy as np
    import map_edits
    (OUT / 'client').mkdir(parents=True, exist_ok=True)
    for n in names:
        Image.open(files[n[:-4].lower() + '.dds']).convert('RGB').save(OUT / 'client' / n)
    fixes = {}
    for n in names:
        rgb = np.asarray(Image.open(OUT / 'client' / n).convert('RGB'))
        out, notes = map_edits.edit(n[:-4], rgb, OUT / 'client')
        dest = OUT / 'original' / n
        img = Image.fromarray(out)
        if not dest.exists() or np.asarray(Image.open(dest).convert('RGB')).tobytes() != out.tobytes():
            img.save(dest)                                    # changed pictures only (a new x4plus pass for those)
        if notes:
            fixes[n] = notes
    (OUT / 'period_fixes.json').write_text(json.dumps(fixes, indent=1), encoding='utf-8')
    if '--no-upscale' not in sys.argv:
        from build_ui_classic import upscale_each
        upscale_each(OUT / 'original', OUT / 'x4plus')
    (OUT / 'maps.json').write_text(json.dumps({
        'zones': {str(k): v for k, v in zones.items()}, 'regions': {str(k): v for k, v in regions.items()},
        'source': 'client ui/maps (z###.dds, z###_NN.dds, r###.dds, regions.dat, areas.dat)'}, indent=1), encoding='utf-8')
    print(len(zones), 'zones,', sum(1 for z in zones.values() if z['map']), 'with maps,',
          sum(len(z['areas']) for z in zones.values()), 'area maps,', len(regions), 'region maps:',
          {k: v['name'] for k, v in regions.items()})
    print('no map:', [z for z, v in zones.items() if not v['map']])


if __name__ == '__main__':
    main()
