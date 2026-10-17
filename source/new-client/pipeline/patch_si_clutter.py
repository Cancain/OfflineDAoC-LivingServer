"""The Shrouded Isles zones' ground clutter (owner 2026-10-11, old client video + screenshot of Isle of Glass / Avalon Isle:
sparse dry yellow grass on dirt, ours was the classic realm's dense green plants). zones.dat has no expansion flag for
them, so build_zone picked grass_<realm>.csv; the expansion set is grass_<realm>exp.csv, chosen by the SI regions (51
Albion, 151 Midgard, 181 Hibernia) - and Hibernia's SI zones (181+) also got Midgard's set from zone_id // 100.
Rewrites each built SI zone's clutter (items + atlas) without rebuilding the zone. build_zone.py does the same now.
The atlas goes in textures/original (the game falls back to it until an x4plus upscale exists)."""
import io, json, re, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
from assets_pipeline import CLIENT
import build_zone as bz

ZONES = Path(__file__).resolve().parent.parent / 'godot/content/zones'

done = []
for zd in sorted(ZONES.glob('zone[0-9][0-9][0-9]')):
    zid = int(zd.name[4:])
    zj = zd / 'zone.json'
    if not zj.exists():
        continue
    realm, exp = bz.clutter_realm(zid)
    if not exp:
        continue
    info = json.loads(zj.read_text(encoding='utf-8'))
    if not info.get('clutter'):
        continue
    name = f'grass_{realm}exp'
    items = bz.clutter_items(CLIENT / 'zones/textures' / f'{name}.csv')
    atlas = Image.open(CLIENT / 'zones/textures' / f'{name}.dds')
    out = zd / 'textures/original'
    out.mkdir(parents=True, exist_ok=True)
    atlas.save(out / f'{name}.png')
    info['clutter'].update({'atlas': name, 'atlas_size': list(atlas.size), 'items': items})
    zj.write_text(json.dumps(info), encoding='utf-8')
    done.append(f'{zid} {info["name"]}: {name} ({len(items)} kinds)')
print('\n'.join(done))
print(len(done), 'SI zones')
