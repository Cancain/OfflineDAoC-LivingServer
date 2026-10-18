"""The Cabalist's simulacrums (CabalPet.NIF, monsters.csv 241-244) as the client draws them: the coloured marble skin
on the mesh's first UV set (tiling, -1.5..2.5) times giantdark.tga on its second (0..1 over the body). Our character
glTF carries one UV set (the second, build_monsters.py), so the two are baked into one texture in giantdark's layout:
every texel of it covered by the mesh gets the marble sampled at that spot's first-set coordinates, times giantdark
there (owner 2026-10-17: giantdark alone was pale white; the old client's simulacrum is a darker grey stone).

    python pipeline/bake_cabalpet.py          (then the folders' x4plus upscale; build_monsters.py --models=241,...)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif
import nif_static
from texture_index import TextureIndex

SIZE = (1024, 2048)                                    # giantdark is 256 x 512: baked at 4x, the marble's grain kept
FOLDERS = {'yellowmarble': 'cabalpet__yellowmarble__giantdark', 'redmarble': 'cabalpet__redmarble__giantdark',
           'bluemarble': 'cabalpet__bluemarble__giantdark', 'greenmarble': 'cabalpet__greenmarble__giantdark'}


def mesh():
    nif = read_nif((CLIENT / 'figures' / 'CabalPet.NIF').read_bytes())
    for b in nif.blocks:
        if b.type in ('NiTriShapeData', 'NiTriStripsData') and len(b.get('uv_sets') or []) >= 2:
            uv0 = np.asarray(b['uv_sets'][0], np.float64)[:, :2]
            uv1 = np.asarray(b['uv_sets'][1], np.float64)[:, :2]
            return uv0, uv1, nif_static.triangles_of(b).astype(np.int64)
    raise SystemExit('CabalPet.NIF: no shape with two UV sets')


def bake(marble, dark, uv0, uv1, tri):
    w, h = SIZE
    m = np.asarray(marble.convert('RGB'), np.float64) / 255.0
    d = np.asarray(dark.convert('RGB').resize(SIZE, Image.LANCZOS), np.float64) / 255.0
    mh, mw = m.shape[:2]
    out = d.copy()                                     # (texels no triangle covers keep giantdark: unseen anyway)
    got = np.zeros((h, w), bool)
    for t in tri:
        p = uv1[t] * [w, h]                            # the triangle in giantdark's pixels
        x0, y0 = np.floor(p.min(0)).astype(int)
        x1, y1 = np.ceil(p.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w - 1), min(y1, h - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = p
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        l2 = 1.0 - l0 - l1
        inside = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
        if not inside.any():
            continue
        q = uv0[t]                                     # the same spots in the marble's (tiling) coordinates
        u = l0 * q[0, 0] + l1 * q[1, 0] + l2 * q[2, 0]
        v = l0 * q[0, 1] + l1 * q[1, 1] + l2 * q[2, 1]
        mx = (np.mod(u, 1.0) * mw).astype(int) % mw
        my = (np.mod(v, 1.0) * mh).astype(int) % mh
        iy, ix = ys[inside].astype(int), xs[inside].astype(int)
        out[iy, ix] = m[my[inside], mx[inside]] * d[iy, ix]
        got[iy, ix] = True
    print('  texels covered:', int(got.sum()), 'of', w * h)
    return Image.fromarray(np.clip(out * 255.0, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')


def main():
    idx = TextureIndex()
    uv0, uv1, tri = mesh()
    dark = idx.image('giantdark')
    for marble_name, folder in FOLDERS.items():
        d = ROOT / 'godot/content/monsters' / folder / 'textures/original'
        target = d / f'{marble_name}__giantdark.png'
        print(folder)
        bake(idx.image(marble_name), dark, uv0, uv1, tri).save(target)


if __name__ == '__main__':
    main()
