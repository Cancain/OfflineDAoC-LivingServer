"""Siege weapons that move (owner 2026-10-14: "siege weapons don't animate yet"): each siege model rebuilt as a skinned
model with the client's own clips, next to its static copy - weapons.json gets "anim_file" / "anim_clips" and the game
draws the animated one (WeaponModels.path_of) and plays the server's actions on it (ServerWorld._siege_anim).

Clips: anims/siege_*.kfa by name - the rams' idle / load / fire / walk, the scorpions' idle / load / fire, boiling
oil's idle / attack (its fire) - animnifs.csv rows 2414-2428, 2488-2490, the same lengths. "run" repeats "walk".
All the visible geometry of these models is skinned (Body / Head / Arms on their own Bip01 skeletons).

    python pipeline/build_siege_anims.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif, spec
import nif_character as nc

OUT = ROOT / 'godot/content/weapons'
E = nc.EMBEDDED_CLIP
RAM = {'idle': 'siege_ram_heavy_idle.kfa', 'load': 'siege_ram_heavy_load.kfa', 'fire': 'siege_ram_heavy_fire.kfa',
       'walk': 'siege_ram_heavy_walk.kfa', 'run': 'siege_ram_heavy_walk.kfa'}   # every ram (one skeleton, animnifs 2414-2417)
SIEGE = {   # objects.csv model -> clips (glTF name -> kfa)
    2600: RAM,
    2601: RAM,
    2602: {'idle': 'siege_ram_heavy_idle.kfa', 'load': 'siege_ram_heavy_load.kfa', 'fire': 'siege_ram_heavy_fire.kfa',
           'walk': 'siege_ram_heavy_walk.kfa', 'run': 'siege_ram_heavy_walk.kfa'},
    2605: {'idle': 'siege_ram_heavy_idle.kfa', 'load': 'siege_ram_heavy_load.kfa', 'fire': 'siege_ram_heavy_fire.kfa',
           'walk': 'siege_ram_heavy_walk.kfa', 'run': 'siege_ram_heavy_walk.kfa'},
    2604: {'idle': 'siege_scor_idle.kfa', 'load': 'siege_scor_load.kfa', 'fire': 'siege_scor_Fire.kfa'},
    2645: {'idle': 'siege_scor_ranged_idle.kfa', 'load': 'siege_scor_ranged_load.kfa', 'fire': 'siege_scor_ranged_fire.kfa'},
    2607: {'idle': 'siege_boiling_idle.kfa', 'fire': 'siege_boiling_attack.kfa'},
}
# the catapult (2598) and the trebuchets (2599 ranged, 2606 mounted) have no clips in the client (animnifs.csv lists siege clips for
# the rams, scorpions and boiling oil only; their models' own keys are a one-frame rest pose): drawn still, as there


def parts_of(nif):
    """{parent node name: texture} for every visible skinned shape."""
    sp = spec()
    parent_of = {}
    for b in nif.blocks:
        if b.type == 'NiNode':
            for c in b.get('children') or []:
                if c is not None:
                    parent_of[id(c)] = b.get('name')
    parts = {}
    for b in nif.blocks:
        if not sp.is_a(b.type, 'NiTriBasedGeom') or b.get('skin_instance') is None or b.get('flags', 0) & 1:
            continue
        for pr in b.get('properties') or []:
            if pr is not None and pr.type == 'NiTexturingProperty':
                bt = pr.get('base_texture') or {}
                src = bt.get('source') if isinstance(bt, dict) else None
                if src is not None and src.get('file_name'):
                    parts[parent_of[id(b)]] = str(src.get('file_name')).rsplit('.', 1)[0].lower()
    return parts


def main():
    data = json.loads((OUT / 'weapons.json').read_text(encoding='utf-8'))
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    for model, clips in SIEGE.items():
        entry = data['models'].get(str(model))
        if entry is None:
            print(model, 'not in weapons.json (build_weapons.py --add first)')
            continue
        path = files.get(entry['nif'] + '.nif')
        parts = parts_of(read_nif(path.read_bytes()))
        folder = entry['nif'] + '__anim'
        (OUT / folder).mkdir(parents=True, exist_ok=True)
        report = nc.build(f'../items/{path.name}', parts, {k: (v, 1.0) for k, v in clips.items()},
                          str(OUT / folder / 'model.gltf'), '../textures/x4plus')
        missing = [t for t in parts.values() if not (OUT / 'textures/x4plus' / f'{t}.png').exists()]
        entry['anim_file'] = f'{folder}/model.gltf'
        entry['anim_clips'] = sorted(clips)
        print(model, entry['name'], parts, {k: (v['bones'], v['seconds']) for k, v in report.items()},
              'missing textures: %s' % missing if missing else '')
    (OUT / 'weapons.json').write_text(json.dumps(data, indent=1), encoding='utf-8')


if __name__ == '__main__':
    main()
