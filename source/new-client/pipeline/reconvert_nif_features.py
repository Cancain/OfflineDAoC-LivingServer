"""Re-convert the zone models and server world objects whose NIFs use a converter feature added later - the
NiTextureEffect environment map and NiMaterialColorController colours (2026-10-11): the ice / stone / root halls,
Dellingstad's crystals, the meteors, the winter trees and feast table, the crystal props ... Each is converted exactly
as its builder did (build_zone: models/<nif>.gltf, item_ / effect_ prefixes, textures ../textures/original;
build_weapons: <nif>/model.gltf, textures ../textures/x4plus), its new textures exported and upscaled.

    set DAOC_CLIENT=<the Claude version's client app folder>
    python pipeline/reconvert_nif_features.py [--features "NiTextureEffect,NiMaterialColorController"]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from texture_index import TextureIndex
from build_zone import upscale_dir, save_if_changed
import nif_static

FEATURES = [b'NiTextureEffect', b'NiMaterialColorController']
if '--features' in sys.argv:
    FEATURES = [f.encode() for f in sys.argv[sys.argv.index('--features') + 1].split(',')]
CONTENT = ROOT / 'godot/content'


def nif_sources():
    """NIF name -> raw bytes getter, for every NIF in the client: loose files and the .npk / .mpk archives."""
    loose, packed = {}, {}
    for p in CLIENT.rglob('*.nif'):
        loose.setdefault(p.parent.name.lower(), {})[p.stem.lower()] = p
    for p in list(CLIENT.rglob('*.npk')) + list(CLIENT.rglob('*.mpk')):
        try:
            names = [k for k in read_mpk(str(p)) if k.lower().endswith('.nif')]
        except Exception:
            continue
        for k in names:
            packed.setdefault(k.lower()[:-4], p)
    return loose, packed


def raw_of(stem, folder, loose, packed):
    if folder and stem in loose.get(folder, {}):
        return loose[folder][stem].read_bytes()
    if stem in packed:
        d = read_mpk(str(packed[stem]))
        return next(v for k, v in d.items() if k.lower() == stem + '.nif')
    for f in loose.values():
        if stem in f:
            return f[stem].read_bytes()
    return None


def export(names, odir, idx, missing):
    odir.mkdir(parents=True, exist_ok=True)
    for n in sorted(names):
        doubled = n.endswith(('__d2', '__x2'))   # __x2: the raw detail map (detail_x2.py)
        img = idx.image(n[:-4] if doubled else n) or nif_static.EMBEDDED.get(n)
        if img is None:
            missing.append(n)
            continue
        if doubled and n.endswith('__d2'):
            img = Image.fromarray(np.clip(np.asarray(img.convert('RGB'), np.float32) * 2.0, 0, 255).astype(np.uint8))
        save_if_changed(img, odir / f'{n}.png')


def main():
    loose, packed = nif_sources()
    idx = TextureIndex()
    done, missing, zones_touched = [], [], set()
    for zdir in sorted(p for p in (CONTENT / 'zones').iterdir() if (p / 'models').is_dir()):
        names = set()
        for g in sorted((zdir / 'models').glob('*.gltf')):
            stem, folder = g.stem.lower(), None
            if stem.startswith('item_'):
                stem, folder = stem[5:], 'items'
            elif stem.startswith('effect_'):
                stem, folder = stem[7:], 'effects'
            raw = raw_of(stem, folder, loose, packed)
            if raw is None or not any(f in raw for f in FEATURES):
                continue
            info = nif_static.convert(raw, str(g), '../textures/original')
            names |= set(info['textures'])
            done.append(f'{zdir.name}/{g.name}')
        if names:
            export(names, zdir / 'textures/original', idx, missing)
            upscale_dir(zdir / 'textures/original', zdir / 'textures/x4plus')
            zones_touched.add(zdir.name)
    # the server's world objects / items (build_weapons): plain <nif>/model.gltf folders (no applied-texture variants)
    wdir = CONTENT / 'weapons'
    names = set()
    for d in sorted(p for p in wdir.iterdir() if (p / 'model.gltf').exists() and '__' not in p.name):
        raw = raw_of(d.name, 'items', loose, packed)
        if raw is None or not any(f in raw for f in FEATURES):
            continue
        info = nif_static.convert(raw, str(d / 'model.gltf'), '../textures/x4plus')
        names |= set(info['textures'])
        done.append(f'weapons/{d.name}')
    if names:
        export(names, wdir / 'textures/original', idx, missing)
        upscale_dir(wdir / 'textures/original', wdir / 'textures/x4plus', factor_after=4)
    print(len(done), 'models reconverted in', len(zones_touched), 'zones + weapons; missing textures:', sorted(set(missing))[:20])
    for x in done:
        print(' ', x)


if __name__ == '__main__':
    main()
