"""The realm war map (owner 2026-10-10; the in-game map came with New Frontiers - "1.65 EXCEPTIONS MADE.txt"), built
the way the old OfflineDAoC client showed the CLASSIC frontier (CLAUDE VERSION "CLIENT REVERSE ENGINEERING NOTES.md"
section 3, patch_classic_warmap_client.py / build_classic_warmap_textures.py):
  - the window and its controls from the client's ui/isles/realmwar_{alb,mid,hib}.xml: four 128x128 tiles (controls
    1000-1003) at their XML positions, each cut from the realm's 256x256 texture (albmap / midmap / hibmap2.tga - the
    old project's classic versions: the classic zone maps scaled into the quadrant each control's template reads), and
    the realm symbol (realm_symb.tga);
  - tile i shows classic zone TILE_ZONES[realm][i];
  - each keep of the frontier (old DB Keep table, regions 1 / 100 / 200) on its zone's tile at
    offset = (world - zone origin) / 512 px (a 65536-unit zone is a 128 px tile), clamped to 4..124 for the border
    keeps on the zone edge; icons from map_icons.tga (realmwar_keep: grey / green / blue / red by owner; relic keeps
    relic_symbol).
Writes godot/content/ui/warmap/warmap.json and the textures as png.   python build_warmap.py"""
import json, re, sqlite3
from pathlib import Path
from PIL import Image
from assets_pipeline import CLIENT, ROOT

OUT = ROOT / 'godot/content/ui/warmap'
DB = ROOT / 'external/old_project/runtime/data/opendaoc.sqlite3.db'
PAGES = {'alb': ('realmwar_alb.xml', 'albmap.tga', 1), 'mid': ('realmwar_mid.xml', 'midmap.tga', 100),
         'hib': ('realmwar_hib.xml', 'hibmap2.tga', 200)}
TILE_ZONES = {'alb': (11, 15, 12, 14), 'mid': (112, 111, 115, 113), 'hib': (211, 214, 212, 210)}
RELIC_KEEPS = {57, 58, 82, 198, 110, 111}                  # Castle Excalibur / Myrddin, Grallarhorn / Mjollner, Dun Dagda / Lamfhota
REALM = {0: 'none', 1: 'alb', 2: 'mid', 3: 'hib'}


def flat(path):
    return re.sub(r'\s+', ' ', path.read_text(encoding='latin1'))


def page(realm):
    xml, tex, region = PAGES[realm]
    t = flat(CLIENT / 'ui/isles' / xml)
    quads = {m.group(1): (int(m.group(2)), int(m.group(3))) for m in re.finditer(
        r'<ImageAreaTemplate> <Name>([^<]*)</Name> <TextureName>[^<]*</TextureName> <Size> <X>\d+</X> <Y>\d+</Y> </Size> <TopLeft> <X>(\d+)</X> <Y>(\d+)', t)}
    win = t[t.find('<WindowTemplate>'):]
    size = [int(v) for v in re.search(r'<Width>(\d+)</Width> <Height>(\d+)</Height>', win).groups()]   # Midgard 394 x 352
    tiles, symbol = {}, None
    for m in re.finditer(r'<ImageAreaDef>(.*?)</ImageAreaDef>', win):
        b = m.group(1)
        pos = re.search(r'<Position> <X>(-?\d+)</X> <Y>(-?\d+)</Y>', b)
        name = re.search(r'<TemplateName>([^<]*)<', b).group(1)
        cid = re.search(r'<ControlId>(\d+)<', b)
        if cid and 1000 <= int(cid.group(1)) <= 1003:
            tiles[int(cid.group(1)) - 1000] = {'pos': [int(pos.group(1)), int(pos.group(2))], 'quad': list(quads[name])}
        elif name.endswith('_symbol') and name[:3] in ('alb', 'mid', 'hib'):
            symbol = {'pos': [int(pos.group(1)), int(pos.group(2))], 'quad': list(quads[name])}
    labels = [[int(a), int(b)] for a, b in re.findall(r'<LabelDef> <Position> <X>(\d+)</X> <Y>(\d+)</Y>', win)]
    for i, z in enumerate(TILE_ZONES[realm]):
        tiles[i]['zone'] = z
    Image.open(CLIENT / 'ui/isles' / tex).convert('RGB').save(OUT / f'{realm}map.png')
    return {'size': size, 'tiles': [tiles[i] for i in range(4)], 'symbol': symbol, 'labels': labels, 'texture': f'{realm}map.png',
            'region': region}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    zi = json.loads((ROOT / 'godot/content/zones/zones_index.json').read_text(encoding='utf-8'))
    out = {'source': 'client ui/isles realmwar_*.xml + map_icons.tga, old DB Keep table (see build_warmap.py)',
           'icons': {'keep': {'none': [0, 16], 'hib': [16, 16], 'mid': [32, 16], 'alb': [48, 16]},
                     'relic': [96, 16], 'player': [99, 82, 11, 11]},
           'pages': {}}
    db = sqlite3.connect(f'file:{DB.as_posix()}?mode=ro', uri=True)
    for realm in PAGES:
        p = page(realm)
        keeps = []
        for kid, name, x, y, owner, level in db.execute(
                'select KeepID, Name, X, Y, Realm, Level from Keep where Region=? order by KeepID', (p['region'],)):
            for i, tile in enumerate(p['tiles']):
                z = zi[str(tile['zone'])]
                ox, oy = int(z['x']) * 8192, int(z['y']) * 8192
                if ox <= x < ox + int(z.get('w', 8)) * 8192 and oy <= y < oy + int(z.get('h', 8)) * 8192:
                    px = min(124, max(4, (x - ox) / 512))
                    py = min(124, max(4, (y - oy) / 512))
                    keeps.append({'id': kid, 'name': name, 'level': level, 'owner': REALM.get(owner, 'none'),
                                  'kind': 'relic' if kid in RELIC_KEEPS else 'keep', 'tile': i,
                                  'at': [round(tile['pos'][0] + px, 1), round(tile['pos'][1] + py, 1)]})
                    break
        p['keeps'] = keeps
        out['pages'][realm] = p
        print(realm, len(keeps), 'keeps')
    for f in ('map_icons.tga', 'realm_symb.tga'):
        Image.open(CLIENT / 'ui/isles' / f).convert('RGBA').save(OUT / (f.rsplit('.', 1)[0] + '.png'))
    (OUT / 'warmap.json').write_text(json.dumps(out, indent=1), encoding='utf-8')
    print('wrote', OUT / 'warmap.json')


if __name__ == '__main__':
    main()
