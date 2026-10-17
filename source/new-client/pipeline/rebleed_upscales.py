"""Redo every cut-out texture's x4plus copy with the alpha bleed (owner 2026-10-14: Malmohus' pines had "giant black
lines" - the upscales had black under their transparent parts and a dark outline around every branch; alpha_bleed.py).

For each <dir>/x4plus/<name>.png under godot/content whose <dir>/original/<name>.png has a cut-out alpha: the original,
bled, through Real-ESRGAN x4plus in batches, down to the x4plus copy's own size, bled again - build_zone.upscale_dir's
rules (tiny / flat pictures and the network's failures get the plain resize, also bled).

    python pipeline/rebleed_upscales.py [--only <path part>] [--list]
"""
import shutil, subprocess, sys, tempfile, time
from pathlib import Path

from PIL import Image

import alpha_bleed
import build_zone as bz

CONTENT = bz.ROOT / 'godot/content'
CHUNK = 150


def todo(only=''):
    out = []
    for d in sorted(CONTENT.rglob('x4plus')):
        orig = d.parent / 'original'
        if not d.is_dir() or not orig.is_dir() or only not in str(d).replace('\\', '/'):
            continue
        for p in sorted(d.glob('*.png')):
            o = orig / p.name
            if o.exists():
                try:
                    if alpha_bleed.has_cutout(Image.open(o)):
                        out.append((o, p))
                except OSError:
                    pass
    return out


def run(pairs):
    done = plain = 0
    t0 = time.time()
    for c in range(0, len(pairs), CHUNK):
        chunk = pairs[c:c + CHUNK]
        with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as pending:
            names = {}
            for i, (o, x) in enumerate(chunk):
                n = f'{i:04d}_{o.name}'
                names[n] = (o, x)
                if not bz._plain(o):
                    alpha_bleed.bleed(Image.open(o)).save(Path(pending) / n)
            if any(Path(pending).iterdir()):
                subprocess.run([str(bz.ESRGAN), '-i', pending, '-o', tmp, '-n', 'realesrgan-x4plus', '-s', '4', '-f', 'png'],
                               cwd=bz.ESRGAN.parent, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for n, (o, x) in names.items():
                size = Image.open(x).size
                binary = alpha_bleed.is_binary(Image.open(o))
                big = None
                if not bz._plain(o) and (Path(tmp) / n).exists():
                    big = Image.open(Path(tmp) / n)
                    if bz._mismatch(o, big):
                        big = None
                if big is None:
                    plain += 1
                    img = bz._plain_resize(o, size)
                else:
                    img = big.resize(size, Image.LANCZOS)
                alpha_bleed.bleed(img, binary).save(x)
                done += 1
        print(f'{done}/{len(pairs)} redone ({plain} plain resize), {time.time() - t0:.0f} s', flush=True)


if __name__ == '__main__':
    only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else ''
    pairs = todo(only)
    print(len(pairs), 'cut-out upscales', flush=True)
    if '--list' in sys.argv:
        for o, x in pairs:
            print(x)
    else:
        run(pairs)
