"""Check every upscaled texture set against its originals: each x4plus image, shrunk back to the original size, must
match its own original (mean abs error). Real-ESRGAN's folder mode can pair outputs with the wrong file names.

    python check_upscales.py [folder ...]      # default: every original/x4plus pair under godot/content
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / 'godot/content'
LIMIT = 14.0


def pairs():
    for orig in ROOT.rglob('original'):
        for name in ('x4plus',):
            up = orig.parent / name
            if up.is_dir():
                yield orig, up


def check(orig, up):
    bad, n = [], 0
    for p in sorted(orig.glob('*.png')):
        q = up / p.name
        if not q.exists():
            continue
        n += 1
        a = Image.open(p).convert('RGBA')
        b = Image.open(q).convert('RGBA').resize(a.size, Image.BILINEAR)
        A = np.asarray(a, np.float32)
        B = np.asarray(b, np.float32)
        w = (A[..., 3] > 128)                                 # colour under transparent pixels is meaningless
        if w.sum() < 16:
            continue
        err = float(np.abs(A[..., :3] - B[..., :3])[w].mean())
        if err > LIMIT:
            bad.append((p.name, round(err, 1)))
    return n, bad


if __name__ == '__main__':
    targets = [(Path(a) / 'original', Path(a) / 'x4plus') for a in sys.argv[1:]] or list(pairs())
    total_bad = 0
    for orig, up in targets:
        n, bad = check(orig, up)
        total_bad += len(bad)
        print(f'{orig.parent.relative_to(ROOT) if ROOT in orig.parents else orig.parent}: {n} checked, {len(bad)} mismatched',
              bad[:6])
    print('TOTAL mismatched', total_bad)
