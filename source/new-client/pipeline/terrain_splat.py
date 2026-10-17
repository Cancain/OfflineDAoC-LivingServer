"""Decode DAoC's Catacombs-era ground blend (ter<id>.mpk) for MMOEngine.

    python terrain_splat.py 200 --check     # compare the decoded blend against the client's own baked ground (lod)

ter<id>.mpk holds textures.csv (per patch: the ground textures blended there, in order, with tiles per patch and
whether they tile) and patchXXYY-LL.dds weight maps (128 x 128 DXT3, XX = patch column east, YY = patch row south).
Decoded layout (verified with --check): each file carries three weights in RGB; its alpha is a copy of the next file's
red channel (multipass blending), so it is skipped. Weights then follow textures.csv order: weight 0 belongs to the
base texture (always 0: it fills underneath) and each later texture is laid over the result by its weight, the
non-tiling zone colour map last.
"""
import argparse, csv, io, sys
from collections import defaultdict
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from daoc_mpk import read_mpk
from assets_pipeline import CLIENT


def decode(zone_id):
    """{(px, py): [{'tex', 'tiles', 'tileable', 'weight': 128x128 float 0..1}]} for every patch."""
    ter = read_mpk(str(CLIENT / f'zones/zone{zone_id:03d}/ter{zone_id:03d}.mpk'))
    layers = defaultdict(list)
    for r in list(csv.reader(io.StringIO(ter['textures.csv'].decode('latin1'))))[1:]:
        if len(r) > 10 and r[0].strip().isdigit():
            layers[(int(r[0]), int(r[1]))].append({'tex': r[2].strip().lower(), 'tiles': float(r[9] or 1),
                                                   'tileable': r[10].strip() == '1'})
    files = defaultdict(list)
    for n in ter:
        if n.startswith('patch') and n.endswith('.dds'):
            files[(int(n[5:7]), int(n[7:9]))].append(n)
    out = {}
    for key, lst in layers.items():
        chans = []
        for f in sorted(files.get(key, [])):
            px = np.asarray(Image.open(io.BytesIO(ter[f])).convert('RGBA'), dtype=np.float32) / 255.0
            chans += [px[..., 0], px[..., 1], px[..., 2]]          # alpha duplicates the next file's red: skipped
        for i, layer in enumerate(lst):
            layer['weight'] = chans[i] if i < len(chans) else np.zeros((128, 128), np.float32)
        out[key] = lst
    return out


def composite_means(patch, colors):
    """Low-frequency colour of one patch: base, then each layer over the result by its weight."""
    c = np.ones((128, 128, 3), np.float32) * colors[patch[0]['tex']]
    for layer in patch[1:]:
        w = layer['weight'][..., None]
        c = c * (1 - w) + colors[layer['tex']] * w
    return c


def check(zone_id):
    from texture_index import TextureIndex
    idx = TextureIndex()
    patches = decode(zone_id)
    lod = read_mpk(str(CLIENT / f'zones/zone{zone_id:03d}/lod{zone_id:03d}.mpk'))
    colors = {}
    for p in patches.values():
        for layer in p:
            if layer['tex'] not in colors:
                img = idx.image(layer['tex'])
                colors[layer['tex']] = np.asarray(img.convert('RGB').resize((1, 1), Image.BOX), np.float32)[0, 0] / 255.0
    scores = []
    for (x, y), p in sorted(patches.items()):
        if any(l['tex'] not in colors for l in p):
            continue
        ours = composite_means([l for l in p if l['tileable']], colors).mean(axis=2)
        ref = np.asarray(Image.open(io.BytesIO(lod[f'lod{x:02d}-{y:02d}.dds'])).convert('L').resize((128, 128)), np.float32)
        if ours.std() > 1e-3 and ref.std() > 1e-3:
            scores.append(np.corrcoef(ours.ravel(), ref.ravel())[0, 1])
    print(f'zone {zone_id}: {len(scores)} patches, correlation of decoded blend with the baked ground: '
          f'median {np.median(scores):.2f}, worst {min(scores):.2f}')
    return scores


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('zone', type=int)
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.check:
        check(a.zone)
