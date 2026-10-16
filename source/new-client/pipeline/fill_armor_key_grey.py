"""Armour textures' unpainted filler (owner 2026-10-15: a level 1 Armsman's gloves and boots, a Sluaghbinder's Tacuil
gauntlets - "their normal textures mixed in with white"). 30 Catacombs glove / boot textures (leaGloves01_ren01 and
the leather / cloth / scale / plate sets like it) are painted over only part of the picture; the rest is a flat key
grey (129, 127, 129). Our figures' glove and boot meshes reach into that filler (the leather gloves: about a third
of the glove's vertices), and lit it shows as pale, near-white patches. The filler is replaced by the nearest painted
colour of the same texture - in the client's own pictures (original) and the upscaled ones (x4plus, the same mask at
4x) - so any part of the mesh on it shows the item's own leather / cloth / metal. The tattoo decals (cel_f_tattoo_*),
where grey is the see-through decal background, are left alone. Backups next to the scratchpad run; run
godot/tools/compress_textures.gd on fig3_textures/x4plus afterwards for the block-compressed copies.

    python pipeline/fill_armor_key_grey.py [--backup=<dir>]
"""
import shutil, sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage
from assets_pipeline import ROOT

TEX = ROOT / 'godot/content/characters/fig3_textures'
KEY = np.array([129, 127, 129])
KEYS = [KEY]
# two textures use a near-white filler instead (the key alone: robes and cloth paint real white areas)
WHITE_KEY = np.array([255, 251, 255])
WHITE_KEYED = ('leagloves01_shark_toa_o', 'cthgloves01_toa_a')
MIN_SHARE = 0.05                                   # a texture with at least this much filler
SKIP = ('_tattoo_',)


def key_mask(a: np.ndarray, keys=None) -> np.ndarray:
    """The filler: a neutral grey near the key (block compression left it anywhere from 126 to 134) that is flat - no
    change over a 5 x 5 patch - in patches of 64 pixels or more; painted grey metal varies and stays."""
    g = a.mean(-1)
    near = np.zeros(a.shape[:2], bool)
    for k in (keys or KEYS):
        near |= np.abs(a - k).max(-1) <= 6
    neutral = near & (np.abs(a[..., 0] - a[..., 1]) <= 4) & (np.abs(a[..., 1] - a[..., 2]) <= 4)
    flat = (ndimage.maximum_filter(g, 5) - ndimage.minimum_filter(g, 5)) <= 4
    m = neutral & flat
    m = ndimage.binary_dilation(m, iterations=2) & neutral      # the patch edges the 5 x 5 test left out
    lab, n = ndimage.label(m)
    if n == 0:
        return m
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    return np.isin(lab, 1 + np.flatnonzero(sizes >= 64))


def fill(img: Image.Image, mask: np.ndarray) -> Image.Image:
    """Every masked pixel takes the colour (and alpha) of the nearest unmasked one."""
    a = np.array(img.convert('RGBA'))
    if mask.all() or not mask.any():
        return img
    _, (iy, ix) = ndimage.distance_transform_edt(mask, return_indices=True)
    out = a[iy, ix]
    return Image.fromarray(out, 'RGBA')


def main():
    backup = next((Path(a.split('=', 1)[1]) for a in sys.argv if a.startswith('--backup=')), None)
    done = []
    for src in sorted((TEX / 'original').glob('*.png')):
        if any(s in src.name.lower() for s in SKIP) or not any(w in src.name.lower() for w in ('glove', 'boot', 'gaunt')):
            continue                                   # gloves and boots only (hair, robes keep their own greys / whites)
        a = np.array(Image.open(src).convert('RGB')).astype(int)
        mask = key_mask(a, [KEY, WHITE_KEY] if src.stem.lower() in WHITE_KEYED else None)
        if mask.mean() < MIN_SHARE:
            continue
        big = TEX / 'x4plus' / src.name
        if backup:
            for p in (src, big):
                if p.exists():
                    d = backup / p.parent.name
                    d.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(p, d / p.name)
        # the painting's edge where it met the filler is a blend of the two (pale): a 1 px ring more is filled too
        ring = ndimage.binary_dilation(mask, iterations=1)
        fill(Image.open(src), ring).save(src)
        if big.exists():
            bi = Image.open(big)
            m4 = np.array(Image.fromarray(mask.astype(np.uint8) * 255).resize(bi.size, Image.NEAREST)) > 127
            # the upscale smeared the filler's edge a few pixels: grow the mask by the scale so none of it is left
            m4 = ndimage.binary_dilation(m4, iterations=2 * max(1, bi.size[0] // a.shape[1]) + 2)
            fill(bi, m4).save(big)
        done.append((src.name, round(float(mask.mean()), 2)))
    for n, s in done:
        print(n, s)
    print(len(done), 'textures filled')


if __name__ == '__main__':
    main()
