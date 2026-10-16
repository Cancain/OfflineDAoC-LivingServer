"""Detail maps drawn as the client draws them: a true modulate 2x (owner 2026-10-14, Malmohus' pines: the client's
trunks show light bark, ours were near-black columns).

NetImmerse multiplies a detail texture in at double brightness. The pipeline stored detail maps pre-doubled and
clipped at white ("<name>__d2"), so a detail map could only darken: pinedetail averages 153 of 255 (80% of it above
half), x2 is ~1.2x brighter on average and up to 2x where the bark is light - the clipped copy lost all of that. Now the
raw map is kept as "<name>__x2" and the shader doubles it (spec detail_x2, as the shader-index detail maps already were).

Migrates built content in place, per folder holding textures/original (and the glTFs under it):
  - textures/original/<name>__x2.png (the client's raw map) and textures/x4plus/<name>__x2.png (2x, bicubic);
  - every glTF material spec whose detail slot is "<name>__d2" -> "<name>__x2" + detail_x2.

    python pipeline/detail_x2.py [--only <path part>]
"""
import json, sys
from pathlib import Path

from PIL import Image

import nif_static
from assets_pipeline import ROOT
from texture_index import TextureIndex

CONTENT = ROOT / 'godot/content'


def raw_image(idx, name):
    return idx.image(name) or nif_static.EMBEDDED.get(name)


def migrate(folder, idx):
    orig = folder / 'textures/original'
    x4 = folder / 'textures/x4plus'
    done_tex, missing = set(), []
    for p in sorted(orig.glob('*__d2.png')):
        name = p.stem[:-4]
        img = raw_image(idx, name)
        if img is None:
            missing.append(name)
            continue
        img = img.convert('RGB')
        img.save(orig / f'{name}__x2.png')
        if x4.is_dir():
            img.resize((img.width * 2, img.height * 2), Image.BICUBIC).save(x4 / f'{name}__x2.png')
        done_tex.add(name)
    changed = 0
    # the glTFs drawing from this textures folder: zones' models/, an effect's own folder, weapons/<item>/model.gltf,
    # pregame/<realm>/scene.gltf - every one under the folder (no nested folder has textures of its own)
    for g in sorted(folder.rglob('*.gltf')):
        text = g.read_text(encoding='utf-8')
        if '__d2' not in text:
            continue
        doc = json.loads(text)
        specs = doc.get('extras', {}).get('nif_materials', [])
        hit = False
        for sp in specs:
            d = sp.get('slots', {}).get('detail')
            if d and str(d.get('tex', '')).endswith('__d2') and d['tex'][:-4] in done_tex:
                d['tex'] = d['tex'][:-4] + '__x2'
                sp['detail_x2'] = True
                hit = True
        if hit:
            g.write_text(json.dumps(doc), encoding='utf-8')
            changed += 1
    return len(done_tex), changed, missing


if __name__ == '__main__':
    only = sys.argv[sys.argv.index('--only') + 1] if '--only' in sys.argv else ''
    idx = TextureIndex()
    tot_t = tot_m = 0
    for orig in sorted(CONTENT.rglob('textures/original')):
        folder = orig.parent.parent
        if only not in str(folder).replace('\\', '/') or not any(orig.glob('*__d2.png')):
            continue
        t, m, miss = migrate(folder, idx)
        tot_t += t
        tot_m += m
        if miss:
            print(folder.relative_to(CONTENT), 'no client image for', miss)
    print(f'{tot_t} detail maps kept raw, {tot_m} models switched to the true modulate 2x')
