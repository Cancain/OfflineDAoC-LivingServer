"""The 1.65 in-game interface art: the original built-in UI bitmaps in the client's app/data/ (owner 2026-10-09,
pure 1.65 era - the XML skins in app/ui/ are later: Atlantis = patch 1.89).

    python build_ui_classic.py            # -> godot/content/ui/classic/{original,x4plus}/<name>.png + classic.json

Transparency: the old renderer colour-keyed these bitmaps. (1,0,1) and pure green (0,255,0) are keys everywhere;
pure black is the key on the button / icon sheets and the compass letters (KEY_BLACK). x4plus = Real-ESRGAN at 4x
(the UI is small and viewed close).
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from build_zone import save_if_changed

DATA = CLIENT / 'data'
OUT = ROOT / 'godot/content/ui/classic'
KEYS = [(1, 0, 1), (0, 255, 0)]
KEY_BLACK = {'buttons', 'buttons2', 'buttons3', 'compass_bar', 'scrlbtns', '8x8gems', 'radiobutton1', 'listicon',
             'listicon1', 'combo_high', 'combo_low', 'hldbrite'}
SKIP = {'chatcorners .bmp'}                     # a stray duplicate with a space in the name
LATER = {'rightbotold'}                         # kept by the client, not used


def keyed(path):
    im = Image.open(path).convert('RGB')
    a = np.asarray(im).astype(np.int16)
    mask = np.zeros(a.shape[:2], bool)
    for k in KEYS:
        mask |= (np.abs(a - np.array(k)).max(axis=2) == 0)
    if path.stem.lower() in KEY_BLACK:
        mask |= (a.max(axis=2) == 0)
    rgba = np.dstack([a.astype(np.uint8), np.where(mask, 0, 255).astype(np.uint8)])
    return Image.fromarray(rgba, 'RGBA'), int(mask.sum())


def main():
    src = OUT / 'original'
    src.mkdir(parents=True, exist_ok=True)
    meta = {}
    # data/ = the client's default stone skin; data/skin1/ = its older grey-stone skin, kept as old_<name> (owner
    # 2026-10-09: the inventory uses the grey-stone paper doll)
    files = [(p, '') for p in sorted(DATA.iterdir())] + [(p, 'old_') for p in sorted((DATA / 'skin1').iterdir())]
    for p, prefix in files:
        if p.suffix.lower() not in ('.bmp', '.tga') or p.name in SKIP or p.stem.lower() in LATER:
            continue
        img, keyed_px = keyed(p) if p.suffix.lower() == '.bmp' else (Image.open(p).convert('RGBA'), 0)
        name = prefix + p.stem.lower().replace(' ', '_')
        save_if_changed(img, src / f'{name}.png')
        meta[name] = {'size': list(img.size), 'keyed_pixels': keyed_px, 'file': p.name}
    (OUT / 'classic.json').write_text(json.dumps(meta, indent=1), encoding='utf-8')
    print(len(meta), 'pieces')
    if '--no-upscale' not in sys.argv:
        upscale_each(src, OUT / 'x4plus')


def upscale_each(src, dst):
    """One image at a time (folder mode paired these outputs with the wrong names, 2026-10-09). Pieces Real-ESRGAN
    can't handle (tiny strips, dithered bar fills, list icons: still off after their own run) get a plain 4x Lanczos."""
    import tempfile
    from build_zone import _upscale_one
    import numpy as np
    dst.mkdir(parents=True, exist_ok=True)
    fallback = []
    with tempfile.TemporaryDirectory() as tmp:
        for p in sorted(src.glob('*.png')):
            q = dst / p.name
            if q.exists() and q.stat().st_mtime >= p.stat().st_mtime:
                continue
            img = Image.open(p).convert('RGBA')
            w, h = img.size
            big = _upscale_one(p, Path(tmp)).resize((w * 4, h * 4), Image.LANCZOS)
            A = np.asarray(img, np.float32)
            B = np.asarray(big.convert('RGBA').resize((w, h), Image.BILINEAR), np.float32)
            m = A[..., 3] > 128
            if min(w, h) < 24 or (m.sum() >= 16 and float(np.abs(A[..., :3] - B[..., :3])[m].mean()) > 14.0):
                big = img.resize((w * 4, h * 4), Image.LANCZOS)
                fallback.append(p.name)
            big.save(q)
    print('lanczos fallback:', fallback)


if __name__ == '__main__':
    main()
