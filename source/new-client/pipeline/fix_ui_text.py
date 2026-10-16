"""Painted text on the classic UI bitmaps, kept readable (owner 2026-10-09: "go thru all the UI and fix any obviously
garbled text while referring to the original, lower the upscale if you have to").

Real-ESRGAN x4plus sharpens the stone well but invents letter shapes in the small painted words ("Strength" ->
"Slrength", "Class" -> "Olass"). This step finds the words in each ORIGINAL bitmap and, inside those areas only,
replaces the AI upscale with the client's own pixels enlarged plainly (4x Lanczos + a light sharpen) - nothing
invented, slightly soft. The stone around them keeps the x4plus upscale.

Finding the words: light, unsaturated pixels standing out from their local background (median 9x9); connected
blobs of glyph size (2-16 px tall, 1-18 px wide); blobs on one baseline with small gaps form a word; words of two
or more glyphs (or one tall glyph) are kept, padded 2 px, and blended in with a feathered edge.

The raw AI upscale is kept in x4plus_raw/ so this can be re-run from scratch; a review sheet per bitmap
(original | AI | fixed, regions outlined) goes to the folder given with --review.
Usage: python fix_ui_text.py [--only name,name] [--review <dir>]"""
import sys, shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
UI = ROOT / 'godot/content/ui/classic'
K = 4
# the bitmaps with painted words (checked by eye on the review sheets, 2026-10-09); every other bitmap keeps its
# untouched x4plus upscale (icons, stone highlights and bar fills were false hits: control, trade, title, ...)
TEXT_PIECES = {'buttons', 'buttons2', 'buttons3', 'charsheet', 'chrsheet', 'skillsheet', 'magicsheet', 'combstylesheet',
               'pperdoll', 'training'}
TEXT_PIECES |= {'old_' + n for n in TEXT_PIECES}


def word_boxes(img):
    """Rectangles (x0, y0, x1, y1) in original pixels around painted words."""
    a = np.asarray(img.convert('RGBA')).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    bg = np.asarray(Image.fromarray(lum.astype(np.uint8)).filter(ImageFilter.MedianFilter(9))).astype(np.float32)
    mask = (lum - bg > 28) & (sat < 60) & (lum > 85) & (alpha > 128)
    # connected components (4-neighbour) without scipy
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    boxes = []
    n = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not lab[y, x]:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                y0 = y1 = y
                x0 = x1 = x
                cnt = 0
                while stack:
                    cy, cx = stack.pop()
                    cnt += 1
                    y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
                gh, gw = y1 - y0 + 1, x1 - x0 + 1
                if 2 <= gh <= 16 and 1 <= gw <= 18 and cnt >= 2 and cnt <= gh * gw:
                    boxes.append([x0, y0, x1, y1])
    # glyphs -> words: same baseline band, gap <= 5 px
    boxes.sort(key=lambda b: (b[1], b[0]))
    words = []
    used = [False] * len(boxes)
    for i, b in enumerate(boxes):
        if used[i]:
            continue
        used[i] = True
        word = list(b)
        count = 1
        grew = True
        while grew:
            grew = False
            for j, c in enumerate(boxes):
                if used[j]:
                    continue
                overlap = min(word[3], c[3]) - max(word[1], c[1])
                gap = max(c[0] - word[2], word[0] - c[2])
                if overlap >= min(word[3] - word[1], c[3] - c[1]) * 0.5 and gap <= 5:
                    word = [min(word[0], c[0]), min(word[1], c[1]), max(word[2], c[2]), max(word[3], c[3])]
                    used[j] = True
                    count += 1
                    grew = True
        tall = word[3] - word[1] + 1
        if count >= 2 or tall >= 6:
            if count >= 2 and (word[2] - word[0]) < 4:
                continue
            words.append((max(0, word[0] - 2), max(0, word[1] - 2), min(w - 1, word[2] + 2), min(h - 1, word[3] + 2), count))
    return [wd for wd in words if wd[4] >= 2]


def fix(name, review=None):
    orig = Image.open(UI / 'original' / f'{name}.png').convert('RGBA')
    raw_dir = UI / 'x4plus_raw'
    raw_dir.mkdir(exist_ok=True)
    up_path = UI / 'x4plus' / f'{name}.png'
    raw_path = raw_dir / f'{name}.png'
    if not raw_path.exists():
        shutil.copy2(up_path, raw_path)
    ai = Image.open(raw_path).convert('RGBA')
    boxes = word_boxes(orig) if name in TEXT_PIECES else []
    if not boxes:
        if up_path.read_bytes() != raw_path.read_bytes():
            shutil.copy2(raw_path, up_path)
        return 0
    plain = orig.resize((orig.width * K, orig.height * K), Image.LANCZOS)
    plain = plain.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    m = Image.new('L', ai.size, 0)
    d = ImageDraw.Draw(m)
    for x0, y0, x1, y1, _ in boxes:
        d.rectangle([x0 * K, y0 * K, (x1 + 1) * K - 1, (y1 + 1) * K - 1], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(3))
    out = Image.composite(plain, ai, m)
    out.save(up_path)
    if review:
        r = Path(review)
        r.mkdir(parents=True, exist_ok=True)
        o4 = orig.resize(ai.size, Image.NEAREST)
        sheet = Image.new('RGBA', (ai.width * 3 + 20, ai.height), (255, 0, 255, 255))
        for i, im in enumerate((o4, ai, out)):
            sheet.alpha_composite(im, (i * (ai.width + 10), 0))
        dd = ImageDraw.Draw(sheet)
        for x0, y0, x1, y1, _ in boxes:
            dd.rectangle([2 * (ai.width + 10) + x0 * K, y0 * K, 2 * (ai.width + 10) + (x1 + 1) * K, (y1 + 1) * K],
                         outline=(0, 255, 0, 255), width=2)
        sheet.convert('RGB').save(r / f'{name}.jpg', quality=85)
    return len(boxes)


def main():
    only = None
    review = None
    args = sys.argv[1:]
    if '--only' in args:
        only = set(args[args.index('--only') + 1].split(','))
    if '--review' in args:
        review = args[args.index('--review') + 1]
    names = sorted(p.stem for p in (UI / 'original').glob('*.png'))
    total = 0
    for name in names:
        if only and name not in only:
            continue
        if not (UI / 'x4plus' / f'{name}.png').exists():
            continue
        n = fix(name, review)
        if n:
            print(f'{name}: {n} word areas')
            total += n
    print('total', total)


if __name__ == '__main__':
    main()
