"""The ground target marker (owner 2026-10-14: "yellow and black with a black dot in the middle", shown by the Ground
Target key on any character in the old client) -> godot/content/ui/gtarget/.

The client draws two things where the ground target is:
  - the "Ground Target" object (objects.csv 1293 -> items.csv 544 -> items/gtarget.nif): a small glowing box, the
    ball in the middle - converted as is (model.gltf, its whtring texture);
  - stylemap/target.bmp projected on the ground (game.dll loads it beside stylemap/SHADOW.BMP, the blob shadow): a
    black X with four white triangles, the white drawn yellow - kept as target.png (white -> the owner's yellow,
    black -> translucent black) for a Decal.

    python pipeline/build_gtarget.py
"""
import numpy as np
from PIL import Image

import nif_static
from assets_pipeline import CLIENT, ROOT
from texture_index import TextureIndex

OUT = ROOT / 'godot/content/ui/gtarget'
YELLOW = (240, 214, 40)


def main():
    (OUT / 'textures/original').mkdir(parents=True, exist_ok=True)
    info = nif_static.convert((CLIENT / 'items/gtarget.NIF').read_bytes(), str(OUT / 'model.gltf'), 'textures/original')
    idx = TextureIndex()
    for t in info['textures']:
        img = idx.image(t) or nif_static.EMBEDDED.get(t)
        if img is not None:
            img.save(OUT / 'textures/original' / f'{t}.png')
    src = np.asarray(Image.open(CLIENT / 'stylemap/target.bmp').convert('L'), np.float32) / 255.0
    rgba = np.zeros(src.shape + (4,), np.uint8)
    for c in range(3):
        rgba[..., c] = (src * YELLOW[c]).astype(np.uint8)            # white -> yellow, black stays black
    rgba[..., 3] = (110 + src * 120).astype(np.uint8)                  # the X translucent, the triangles stronger
    Image.fromarray(rgba, 'RGBA').resize((256, 256), Image.NEAREST).save(OUT / 'target.png')
    print('ground target marker:', OUT)


if __name__ == '__main__':
    main()
