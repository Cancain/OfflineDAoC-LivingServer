"""Zone textures stretched far wider than the rest (owner 2026-10-15: Humberton's house floors "super low quality"):
dirtflor, the farmhouse / cottage dirt floor in 13 zones, is 64 px over a 127 m2 floor - 30 px a metre at the usual
2x, a quarter of the walls (83-133). Two Real-ESRGAN passes (4x, then 4x of that, down to 8x of the client's: 64 -> 512
px, ~120 px a metre) put it in line with the walls, the client's own colours kept (tone_restore).

Every pass runs on a 3 x 3 tiling of the picture and keeps the middle (owner 2026-10-15, the first version "half blurry
half detailed"): on the bare 64 px picture the network invented a stone edge and streaks at the borders and the tile
seams showed on the floor. Wrapped, it sees no border, the detail is even and the result tiles seamlessly. Written over
every zone's textures/x4plus copy; upscale_dir leaves a newer x4plus alone, so a zone rebuild keeps it - run this again
after one that redid the zone's textures.

    python pipeline/sharpen_low_density_textures.py
"""
import subprocess, tempfile
from pathlib import Path
from PIL import Image
from assets_pipeline import ROOT
from build_zone import ESRGAN
import tone_restore

TEXTURES = ['dirtflor']
FACTOR = 8
ZONES = ROOT / 'godot/content/zones'


def tile3(img):
    w, h = img.size
    t = Image.new('RGBA', (w * 3, h * 3))
    for i in range(3):
        for j in range(3):
            t.paste(img, (i * w, j * h))
    return t


def middle(img):
    w, h = img.size[0] // 3, img.size[1] // 3
    return img.crop((w, h, 2 * w, 2 * h))


def esrgan(img):
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        img.save(Path(a) / 't.png')
        subprocess.run([str(ESRGAN), '-i', a, '-o', b, '-n', 'realesrgan-x4plus', '-s', '4', '-f', 'png'],
                       cwd=ESRGAN.parent, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return Image.open(Path(b) / 't.png').convert('RGBA')


def upscale_wrapped(src):
    """src (a tileable picture) at FACTOR x: two wrapped x4plus passes, then Lanczos and tone_restore on the tiling."""
    src = src.convert('RGBA')
    w, h = src.size
    p1 = middle(esrgan(tile3(src)))
    big = esrgan(tile3(p1)).resize((w * FACTOR * 3, h * FACTOR * 3), Image.LANCZOS)
    return middle(tone_restore.restore(tile3(src), big))


def main():
    for name in TEXTURES:
        sources = sorted(ZONES.glob(f'*/textures/original/{name}.png'))
        if not sources:
            print(name, 'in no zone')
            continue
        done = upscale_wrapped(Image.open(sources[0]))
        for src in sources:
            dst = src.parent.parent / 'x4plus' / src.name
            done.save(dst)
            print(dst.relative_to(ROOT))


if __name__ == '__main__':
    main()
