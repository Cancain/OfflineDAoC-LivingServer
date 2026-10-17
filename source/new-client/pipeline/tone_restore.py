"""Put the client's own colours back into an upscale (owner 2026-10-14: Malmohus' pines - "giant black lines", the
trunks drawn as black slabs).

Real-ESRGAN darkens dark pictures: a sample of 1,500 upscales came back ~19% darker where the original averages under
20 (of 255) and 4-6% under 80, one in eleven over 10% darker - the pines' near-black trunk strip went pure black,
logs, oak bark, moss and dark stone the same. The mismatch check (colour off by over 30) can't see 16 -> 12.
The fix keeps the network's fine detail and takes everything at the original's own resolution from the original:

    restored = upscale + resize_up(original - resize_down(upscale))

so the restored copy, brought back down to the original's size, IS the original. Cut-outs are bled first (alpha_bleed)
so the colour under their hidden parts doesn't leak into the visible edge. Alpha stays the upscale's.

    python pipeline/tone_restore.py [--only <path part>] [--dry]    every <dir>/x4plus/*.png under godot/content
"""
import sys, time
from pathlib import Path

import numpy as np
from PIL import Image

import alpha_bleed


def _resize(ch, size, method):
    return np.asarray(Image.fromarray(ch.astype(np.float32), 'F').resize(size, method), np.float32)


def restore(orig, big):
    """big (an upscale of orig) with orig's colours at orig's resolution; RGBA out."""
    o = orig.convert('RGBA')
    cut = alpha_bleed.has_cutout(orig)
    binary = alpha_bleed.is_binary(orig) if cut else False
    if cut:
        o = alpha_bleed.bleed(o, binary)
        big = alpha_bleed.bleed(big, binary)
    A = np.asarray(o, np.float32)
    B = np.asarray(big.convert('RGBA'), np.float32)
    w, h = o.size
    W, H = big.size
    out = B.copy()
    for c in range(3):
        low = _resize(B[..., c], (w, h), Image.BOX)
        out[..., c] = B[..., c] + _resize(A[..., c] - low, (W, H), Image.BICUBIC)
    img = Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), 'RGBA')
    return alpha_bleed.bleed(img, binary) if cut else img


def brightness_ratio(orig, big):
    a = np.asarray(orig.convert('RGBA'), np.float32)
    b = np.asarray(big.convert('RGBA').resize(orig.size, Image.BOX), np.float32)
    m = a[..., 3] >= 128
    return float(b[..., :3][m].mean() / max(a[..., :3][m].mean(), 1e-3)) if m.sum() >= 16 else 1.0


if __name__ == '__main__':
    content = Path(__file__).resolve().parent.parent / 'godot/content'
    only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else ''
    pairs = []
    for d in sorted(content.rglob('x4plus')):
        o = d.parent / 'original'
        if d.is_dir() and o.is_dir() and only in str(d).replace('\\', '/'):
            pairs += [(o / p.name, p) for p in sorted(d.glob('*.png')) if (o / p.name).exists()]
    print(len(pairs), 'upscales', flush=True)
    t0 = time.time()
    before, after, failed = [], [], 0
    for i, (op, xp) in enumerate(pairs):
        try:
            orig, big = Image.open(op), Image.open(xp)
            orig.load(); big.load()
            if big.size[0] < orig.size[0]:
                continue
            fixed = restore(orig, big)
            before.append(brightness_ratio(orig, big))
            after.append(brightness_ratio(orig, fixed))
            if '--dry' not in sys.argv:
                fixed.save(xp)
        except Exception as e:                      # one bad file never stops the pass
            failed += 1
            print('  failed', xp, e, flush=True)
        if (i + 1) % 1000 == 0:
            print(f'{i + 1}/{len(pairs)}  {time.time() - t0:.0f} s', flush=True)
    b, a = np.array(before), np.array(after)
    print(f'done {len(b)} in {time.time() - t0:.0f} s, failed {failed}; brightness vs original: before median '
          f'{np.median(b):.3f}, under 0.9: {(b < 0.9).sum()}  ->  after median {np.median(a):.3f}, under 0.9: '
          f'{(a < 0.9).sum()}, over 1.1: {(a > 1.1).sum()}', flush=True)
