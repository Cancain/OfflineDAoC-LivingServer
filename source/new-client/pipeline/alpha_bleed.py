"""Alpha bleed for cut-out textures (owner 2026-10-14: Malmohus' pines "have giant black lines on them").

Real-ESRGAN sees a cut-out's colour channels whole: foliage against whatever colour sits under the transparent parts
(often near black). It sharpens that edge into a dark outline around every branch and leaves the hidden parts black;
the game's filtering and mipmaps then pull that black into the needles' edges - black lines on every pine, fringe,
hair and feather. A bleed spreads the nearest visible colour under the hidden pixels, before the network (no edge to
outline) and after it (clean mipmaps). Only colour under pixels the game never shows changes:
- a hard cut-out (alpha almost all 0 / 255: alpha-tested): every pixel under alpha 75 - the lowest test the client's
  zone NIFs use (NiAlphaProperty ref 75, cut 0.294: the pines); above it a pixel may show, so its colour stays;
- a soft-alpha texture (glows, smoke - blended, its half-transparent colours count): only alpha 0.

    python pipeline/alpha_bleed.py <png> [<png> ...]     (in place)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def is_binary(img):
    """A hard cut-out: alpha almost all 0 / 255 (judge the client's original - a resized copy has soft edges)."""
    a = np.asarray(img.convert('RGBA'))[..., 3]
    return float(((a <= 8) | (a >= 247)).mean()) >= 0.9


def bleed(img, binary=None):
    """img with the nearest visible colour under its hidden pixels (RGBA in, RGBA out; unchanged if nothing to do).
    binary: the original's is_binary for a resized copy (None: judge img itself)."""
    from scipy import ndimage
    rgba = np.asarray(img.convert('RGBA')).copy()
    if binary is None:
        binary = is_binary(img)
    hidden = rgba[..., 3] < 75 if binary else rgba[..., 3] == 0
    if not hidden.any() or hidden.all():
        return img.convert('RGBA')
    _, (iy, ix) = ndimage.distance_transform_edt(hidden, return_indices=True)
    rgba[..., :3] = rgba[iy, ix, :3]
    return Image.fromarray(rgba, 'RGBA')


def has_cutout(img):
    if img.mode not in ('RGBA', 'LA', 'P', 'PA'):
        return False
    a = np.asarray(img.convert('RGBA'))[..., 3]
    f = float((a < 128).mean())
    return 0.0 < f < 1.0


if __name__ == '__main__':
    for p in sys.argv[1:]:
        im = Image.open(p)
        if has_cutout(im):
            bleed(im).save(p)
