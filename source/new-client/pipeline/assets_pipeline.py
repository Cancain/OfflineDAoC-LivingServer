"""DAoC client assets -> PNG source copies -> enhanced "looks" -> comparison sheets (MMOEngine, step 1).

    python assets_pipeline.py sample            # the visual test set (a few of each kind)
    python assets_pipeline.py all [--kind items] # every texture of a kind (terrain, items, skins, effects, icons)

Reads the DAoC client install read-only (loose DDS/TGA/BMP files and the skin .mpk archives) and writes:
  assets/source/<kind>/<name>.png          lossless conversion of the original
  assets/looks/<look>/<kind>/<name>.png    the same texture after each enhancement look
  previews/<kind>.png                      side-by-side comparison of the looks
Nothing from the client is changed. The looks are plain image processing (Pillow + NumPy, no downloads), meant to
show directions for an "old but new" remaster, not hyper-realism.
"""
import argparse, io, os, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CLIENT = Path(os.environ.get('DAOC_CLIENT', str(Path(__file__).resolve().parent.parent / 'external/old_project/runtime/client-opendaoc/app')))
sys.path.insert(0, str(HERE))
from daoc_mpk import read_mpk

KINDS = {
    'terrain': ('zones/TerrainTex', ('.dds', '.tga', '.bmp')),
    'items': ('items', ('.dds', '.tga')),
    'effects': ('effects', ('.dds', '.tga')),
    'icons': ('icons', ('.bmp', '.tga')),
}
SAMPLE = {
    'terrain': ['zones/TerrainTex/CamelotHills_forest_floor05.dds', 'zones/TerrainTex/CamelotHills_cliff_.dds',
                'zones/TerrainTex/CamelotHills_river_pebbles.dds', 'zones/TerrainTex/ClayMud.dds'],
    'items': ['items/M_bronzeshield.dds', 'items/Bow.dds', 'items/epic_wpn_hunter_sword.dds', 'items/bannercloth.dds'],
    'skins': ['figures/skins/skin001.mpk:b_cth1_body1m.dds', 'figures/skins/skin001.mpk:b_fhed1.dds',
              'figures/skins/skin001.mpk:b_cth1_leg1.dds'],
    'effects': ['effects/e_flame000.dds', 'effects/bluefire02.dds', 'effects/elecglow.dds'],
    'icons': ['icons/spl_100.bmp', 'icons/wpn_1000.bmp', 'icons/itm1_b.bmp'],
}


def load(ref):
    """Open a client texture; 'archive.mpk:name' reads it from a skin archive."""
    if ':' in ref and ref.split(':')[0].lower().endswith('.mpk'):
        archive, name = ref.split(':', 1)
        data = read_mpk(str(CLIENT / archive))[name.lower()]
        img = Image.open(io.BytesIO(data))
    else:
        img = Image.open(CLIENT / ref)
    img.load()
    return img.convert('RGBA')


def split(img):
    rgb, alpha = img.convert('RGB'), img.getchannel('A')
    return rgb, alpha


def upscale(img, factor=4):
    return img.resize((img.width * factor, img.height * factor), Image.LANCZOS)


def look_original(img):
    # pixels as the old client shows them, enlarged without smoothing for comparison
    return img.resize((img.width * 4, img.height * 4), Image.NEAREST)


def look_clean(img):
    rgb, a = split(img)
    rgb = upscale(rgb).filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    return Image.merge('RGBA', (*rgb.split(), upscale(a)))


def look_remaster(img):
    """Edge-aware cleanup of compression noise, then local contrast and fine detail: crisper, richer, still painted."""
    rgb, a = split(img)
    up = upscale(rgb)
    up = Image.blend(up, up.filter(ImageFilter.MedianFilter(3)), 0.5)
    up = up.filter(ImageFilter.UnsharpMask(radius=10, percent=35, threshold=0))     # clarity
    up = up.filter(ImageFilter.UnsharpMask(radius=1.0, percent=90, threshold=3))    # fine detail
    up = ImageEnhance.Color(up).enhance(1.08)
    up = ImageEnhance.Contrast(up).enhance(1.04)
    return Image.merge('RGBA', (*up.split(), upscale(a)))


def look_painterly(img):
    """Softer hand-painted look: smooths noise into flat painted areas, strong clarity, warmer grade."""
    rgb, a = split(img)
    up = upscale(rgb).filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.SMOOTH_MORE)
    up = up.filter(ImageFilter.UnsharpMask(radius=14, percent=55, threshold=0))
    up = ImageEnhance.Color(up).enhance(1.15)
    arr = np.asarray(up).astype(np.float32)
    arr *= np.array([1.04, 1.0, 0.95], dtype=np.float32)                            # gentle warm grade
    up = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    return Image.merge('RGBA', (*up.split(), upscale(a)))


LOOKS = {'original': look_original, 'clean': look_clean, 'remaster': look_remaster, 'painterly': look_painterly}


def safe_name(ref):
    return ref.replace(':', '__').replace('/', '_').rsplit('.', 1)[0]


def process(kind, refs):
    results = []
    for ref in refs:
        try:
            img = load(ref)
        except Exception as e:                       # unreadable formats are reported, not fatal
            print(f'skip {ref}: {e}')
            continue
        name = safe_name(ref)
        src = ROOT / 'assets/source' / kind / f'{name}.png'
        src.parent.mkdir(parents=True, exist_ok=True)
        img.save(src)
        outs = {}
        for look, fn in LOOKS.items():
            out = fn(img)
            if look != 'original':
                dst = ROOT / 'assets/looks' / look / kind / f'{name}.png'
                dst.parent.mkdir(parents=True, exist_ok=True)
                out.save(dst)
            outs[look] = out
        results.append((ref, img, outs))
    return results


def sheet(kind, results, tile=320):
    """One row per texture: a 4x crop of the same spot in each look, labelled."""
    if not results:
        return
    pad, label = 8, 22
    w = pad + len(LOOKS) * (tile + pad)
    h = label + len(results) * (tile + label + pad) + pad
    canvas = Image.new('RGB', (w, h), (24, 24, 28))
    d = ImageDraw.Draw(canvas)
    for c, look in enumerate(LOOKS):
        d.text((pad + c * (tile + pad) + 4, 4), look.upper(), fill=(230, 220, 190))
    for r, (ref, img, outs) in enumerate(results):
        y = label + r * (tile + label + pad)
        d.text((pad, y + 2), ref, fill=(170, 170, 180))
        cw, ch = min(img.width, tile // 4 * 1), min(img.height, tile // 4 * 1)
        cx, cy = (img.width - cw) // 2, (img.height - ch) // 2
        for c, look in enumerate(LOOKS):
            crop = outs[look].crop((cx * 4, cy * 4, (cx + cw) * 4, (cy + ch) * 4)).resize((tile, tile), Image.LANCZOS)
            bg = Image.new('RGBA', crop.size, (60, 60, 66, 255))
            bg.alpha_composite(crop)
            canvas.paste(bg.convert('RGB'), (pad + c * (tile + pad), y + label))
    out = ROOT / 'previews' / f'{kind}.png'
    canvas.save(out)
    print('preview', out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('mode', choices=['sample', 'all'])
    ap.add_argument('--kind', choices=list(KINDS) + ['skins'])
    args = ap.parse_args()
    if args.mode == 'sample':
        for kind, refs in SAMPLE.items():
            sheet(kind, process(kind, refs))
        return
    kinds = [args.kind] if args.kind else list(KINDS)
    for kind in kinds:
        if kind == 'skins':
            refs = [f'figures/skins/{p.name}:{n}' for p in sorted((CLIENT / 'figures/skins').glob('*.mpk'))
                    for n in read_mpk(str(p)) if n.endswith(('.dds', '.tga'))]
        else:
            folder, exts = KINDS[kind]
            refs = [str(p.relative_to(CLIENT)).replace('\\', '/') for p in sorted((CLIENT / folder).iterdir())
                    if p.suffix.lower() in exts]
        res = process(kind, refs)
        print(kind, len(res), 'textures')


if __name__ == '__main__':
    main()
