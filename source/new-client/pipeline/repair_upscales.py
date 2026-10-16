"""Redo the converted x4plus textures Real-ESRGAN got wrong (2026-10-13): tiny pictures and flat fills, and upscales
that aren't their source picture (build_zone._plain / _mismatch) get a plain resize of the client's own texture at
the size already there. Every textures/original + textures/x4plus pair under godot/content.

    python pipeline/repair_upscales.py            (list them)
    python pipeline/repair_upscales.py --write    (rewrite them)
"""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_zone import _mismatch, _plain, _plain_resize

CONTENT = Path(__file__).resolve().parent.parent / 'godot/content'
write = '--write' in sys.argv
n = 0
for o in sorted(CONTENT.glob('**/textures/original/*.png')):
    x = o.parent.parent / 'x4plus' / o.name
    if not x.exists():
        continue
    big = Image.open(x)
    if not (_plain(o) or _mismatch(o, big)):
        continue
    n += 1
    print(o.relative_to(CONTENT), Image.open(o).size, '->', big.size)
    if write:
        _plain_resize(o, big.size).save(x)
print(n, 'textures', 'rewritten' if write else 'to redo (--write)')
