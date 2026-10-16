"""The 1.65 client's bitmap fonts (app/fonts, listed in data/uifontt.dat) for the MMOEngine.

Each font bitmap is 7 colour rows (white, red, yellow, blue, green, orange, grey - the client's text colours) of
the printable ASCII glyphs 33..126 left to right, separated by empty columns, plus one trailing extra glyph.
Owner 2026-10-09: overhead names must use the period font, not a modern one. The white row is cut into glyphs and
saved as a white-on-transparent atlas the engine tints (friendly names light blue, monster names in con colours):
  godot/content/ui/fonts/classic/<font>.png  +  <font>.json {height, space, glyphs: {code: [x, width]}}
Kept pixel-exact (no AI upscale: it invents letter shapes - see WORLD IMPORT LESSONS.md); drawn with nearest
filtering at whole-number scales.
    python build_fonts.py"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT

OUT = ROOT / 'godot/content/ui/fonts/classic'
FONTS = {'14font': 14, '11font': 12, '16font': 16}             # 9font has another layout (not needed)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, rh in FONTS.items():
        src = next(p for p in (CLIENT / 'fonts').iterdir() if p.name.lower() == name + '.bmp')
        rgb = np.asarray(Image.open(src).convert('RGB')).astype(np.int32)[:rh]
        lum = rgb.max(axis=2)
        on = lum > 30
        cols = on.any(axis=0)
        segs, x, w = [], 0, len(cols)
        while x < w:
            if cols[x]:
                s = x
                while x < w and cols[x]:
                    x += 1
                segs.append((s, x))
            else:
                x += 1
        if len(segs) < 94:
            print(name, 'only', len(segs), 'glyphs - skipped')
            continue
        alpha = np.clip(lum * 255 // max(1, int(lum.max())), 0, 255).astype(np.uint8)
        rgba = np.dstack([np.full_like(alpha, 255)] * 3 + [alpha])
        Image.fromarray(rgba, 'RGBA').save(OUT / f'{name}.png')
        glyphs = {str(33 + i): [s, e - s] for i, (s, e) in enumerate(segs[:94])}
        space = max(2, round(np.median([e - s for s, e in segs[:94]]) * 0.6))
        (OUT / f'{name}.json').write_text(json.dumps({'source': src.name, 'height': rh, 'space': space,
                                                      'glyphs': glyphs}), encoding='utf-8')
        print(name, len(segs), 'segments, space', space)


if __name__ == '__main__':
    main()
