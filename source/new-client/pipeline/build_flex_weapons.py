"""Flex weapons - flails, chains, morning stars, whips - with their swinging chains (0.36c, owner 2026-10-11: a
Dullahan's flail was "straight like a sword").

A flex weapon's NIF is a skinned mesh on its own chain bones (Bip01, Bip01 Ext01 ...). items.csv gives each flex
item its chain clips per pose (columns 5-14: Idle, Cidle, Atk High, Atk Mid, CS01, CS03, CS04, CS06, CS07, Parry ->
animnifs.csv rows -> anims/*.kfa, e.g. I_1FW_M.kfa the hanging chain, CI_1FW_Flail.kfa a flail's combat idle).
Converted with nif_character.build (skin + clips) next to the static model; weapons.json gets "flex_file" and the
game plays idle / combat_idle (WeaponModels).

    python pipeline/build_flex_weapons.py
"""
import csv
import io
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from netimmerse import read_nif, spec
import nif_character as nc

OUT = ROOT / 'godot/content/weapons'
CLIP_COLS = {5: 'idle', 6: 'combat_idle', 7: 'attack_high', 8: 'attack_low', 9: 'style_1', 10: 'style_3',
             11: 'style_4', 12: 'style_6', 13: 'style_7', 14: 'parry'}


def main():
    nc.KFA_STATIC_POSES = True                             # the idle clip is a pose file (I_1FW_M.kfa)
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    rows = lambda n: list(csv.reader(io.StringIO(g[n].decode('latin1'))))
    objects = {r[0]: r for r in rows('objects.csv') if r and r[0].isdigit()}
    items = {r[0]: r for r in rows('items.csv') if r and r[0].isdigit()}
    anims = {r[0].strip(): r for r in rows('animnifs.csv') if r and r[0].strip().isdigit()}
    have = {p.name.lower() for p in (CLIENT / 'anims').iterdir()}
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    data = json.loads((OUT / 'weapons.json').read_text(encoding='utf-8'))
    sp = spec()
    built, done, failed = {}, 0, []
    for model, entry in data['models'].items():
        o = objects.get(model)
        it = items.get(o[2].strip()) if o and len(o) > 2 else None
        if it is None or len(it) < 15:
            continue
        clips = {}
        for col, name in CLIP_COLS.items():
            a = anims.get(it[col].strip()) if it[col].strip() not in ('', '0') else None
            if a and a[2].strip().lower() in have:
                clips[name] = (a[2].strip(), 1.0)
        if not clips:
            continue
        nif = it[2].strip()
        path = files.get(nif.lower() + '.nif')
        if path is None:
            continue
        folder = nif.lower() + '__flex'
        if folder not in built:
            n = read_nif(path.read_bytes())
            parent, tex = None, None
            for b in n.blocks:                             # the skinned shape's parent node and its texture
                if b.type == 'NiNode':
                    for c in b.get('children') or []:
                        if c is not None and sp.is_a(c.type, 'NiTriBasedGeom') and c.get('skin_instance') is not None:
                            parent = b.get('name')
                if b.type == 'NiSourceTexture' and tex is None:
                    tex = str(b.get('file_name') or '').rsplit('.', 1)[0].lower()
            if parent is None or not tex:
                failed.append((model, nif, 'no skinned mesh'))
                continue
            (OUT / folder).mkdir(parents=True, exist_ok=True)
            try:
                nc.build(f'../items/{path.name}', {parent: tex}, clips, str(OUT / folder / 'model.gltf'), '../textures/x4plus')
            except Exception as e:
                failed.append((model, nif, f'{type(e).__name__}: {e}'))
                continue
            built[folder] = sorted(clips)
        entry['flex_file'] = f'{folder}/model.gltf'
        entry['flex_clips'] = built[folder]
        done += 1
    (OUT / 'weapons.json').write_text(json.dumps(data, indent=1), encoding='utf-8')
    print(done, 'flex weapon models,', len(built), 'built,', len(failed), 'failed:', failed[:8])


if __name__ == '__main__':
    main()
