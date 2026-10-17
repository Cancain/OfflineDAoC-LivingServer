"""Export the DAoC client's skies for MMOEngine: every zones/sky/sky.mpk sky_*.dat as JSON, plus its textures.

    python build_sky.py

Writes godot/content/sky/:
  <name>.json               one per sky definition (sky_hibernia, sky_muspelheim, ...), values as the client has them:
                            [main] sun / moon / stars / cloud layers, [lights_and_fog_clear|stormy] ambient, dynamic
                            (sun) light and distance fog per dawn/day/dusk/night, [canopy_color_*] sky dome colour
                            rings (zenith, east1-4, west1-4, nadir), [cloud_color_*] cloud colour rings,
                            [storm_system], [rain], [snow]
  textures/original/*.png   the textures those files name (clouds, sun disk/flare/glow, moon, stars, snowflake)
  textures/x4plus/*.png     Real-ESRGAN x4plus, 2x (owner rule), alpha kept
  zone_skies.json           zone id -> sky name (zones.dat skydome=, else the realm's sky)
"""
import json, re, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from daoc_mpk import read_mpk
from assets_pipeline import CLIENT, ROOT
from build_zone import upscale_dir, save_if_changed

OUT = ROOT / 'godot/content/sky'


def parse_value(v):
    v = v.split(';', 1)[0].strip()
    parts = [p.strip() for p in v.split(',')]
    try:
        nums = [float(p) for p in parts]
        return nums if len(nums) > 1 else nums[0]
    except ValueError:
        return v


def parse_dat(text):
    data, section = {}, 'main'
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        m = re.match(r'^\[(.+?)\]', line)
        if m:
            section = m.group(1).strip().lower()
            data.setdefault(section, {})
            continue
        if '=' in line:
            k, v = line.split('=', 1)
            data.setdefault(section, {})[k.strip().lower()] = parse_value(v)
    return data


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (ROOT / 'godot/content/.gdignore').touch()
    sky = read_mpk(str(CLIENT / 'zones/sky/sky.mpk'))
    textures = set()
    for name, raw in sorted(sky.items()):
        if not name.endswith('.dat'):
            continue
        data = parse_dat(raw.decode('latin1').lstrip('﻿'))
        for k, v in data.get('main', {}).items():
            if k.endswith('_texture') or k.endswith('_texture2'):
                if isinstance(v, str) and v:
                    textures.add(v.lower())
        for sec in ('snow',):
            t = data.get(sec, {}).get('flake_texture')
            if isinstance(t, str):
                textures.add(t.lower())
        (OUT / f'{name[:-4]}.json').write_text(json.dumps(data, indent=1), encoding='utf-8')
    odir = OUT / 'textures/original'
    odir.mkdir(parents=True, exist_ok=True)
    missing = []
    for t in sorted(textures):
        src = next((p for p in (CLIENT / 'zones/sky').iterdir() if p.name.lower() == t), None)
        if src is None:
            missing.append(t)
            continue
        save_if_changed(Image.open(src).convert('RGBA'), odir / f'{Path(t).stem.lower()}.png')
    upscale_dir(odir, OUT / 'textures/x4plus')
    # which sky each zone uses: zones.dat skydome=, otherwise the realm's own sky
    zones = read_mpk(str(CLIENT / 'zones/zones.mpk'))['zones.dat'].decode('latin1')
    zone_skies = {}
    for m in re.finditer(r'\[zone(\d+)\](.*?)(?=\n\[|\Z)', zones, re.S | re.I):
        zid = int(m.group(1))
        dome = re.search(r'skydome\s*=\s*(\S+)', m.group(2))
        if dome:
            zone_skies[zid] = dome.group(1).lower().rsplit('.', 1)[0]
        else:
            zone_skies[zid] = {0: 'sky_albion', 1: 'sky_midgard', 2: 'sky_hibernia'}.get(zid // 100, 'sky_default')
    (OUT / 'zone_skies.json').write_text(json.dumps(zone_skies, indent=1), encoding='utf-8')
    print(f'{len([n for n in sky if n.endswith(".dat")])} skies, {len(textures)} textures ({missing} missing), '
          f'{len(zone_skies)} zones mapped; zone 200 -> {zone_skies.get(200)}, 104 -> {zone_skies.get(104)}')


if __name__ == '__main__':
    main()
