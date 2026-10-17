"""8x8gems.bmp (the mini group window's power gems) has a purple background the client draws as see-through; key it
to alpha in both the original and the x4plus copies.   python key_ui_gems.py"""
from PIL import Image
from assets_pipeline import ROOT

for sub in ('original', 'x4plus'):
    p = ROOT / 'godot/content/ui/classic' / sub / '8x8gems.png'
    im = Image.open(p).convert('RGBA')
    px = im.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 170 and g < 110 and r > 100 and r < 230:      # the purple field (173, 41, 242) and its upscaled fringe
                px[x, y] = (r, g, b, 0)
                n += 1
    im.save(p)
    print(p.name, sub, 'keyed', n)
