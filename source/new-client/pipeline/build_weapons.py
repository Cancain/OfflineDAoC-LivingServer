"""Weapons and shields the player can hold, from the client (MMOEngine; owner 2026-10-09: "make my training sword
appear in game").

Chain: item 'model' -> gamedata objects.csv row (col 2 = items.csv NIF number, col 17 Belt, col 19 Combat Stance,
col 20 Left Hand) -> items.csv row (col 2 NIF name, col 15 Back Offset) -> app/items/<name>.nif. Converted with
nif_static (Godot axes, metres) - the engine hangs it on the figure's attach bones (Bip01 R Hand / L Shield /
L Belt / R Back ...), undoing the axis change there because the figures stay in NIF space. Textures: Real-ESRGAN
x4plus at 4x (owner: weapons get the 4x pass like players and armour).

    python build_weapons.py      # every weapon / shield in godot/content/items/items.json + merchants.json
Writes godot/content/weapons/<nif>/model.gltf, textures in godot/content/weapons/textures/{original,x4plus} and
godot/content/weapons/weapons.json {model id: {nif, file, belt, stance, left, back_offset}}."""
import csv, io, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from texture_index import TextureIndex
from build_zone import upscale_dir, save_if_changed
import nif_static

OUT = ROOT / 'godot/content/weapons'
ITEMS = ROOT / 'godot/content/items'


def tables():
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    objects = {r[0]: r for r in csv.reader(io.StringIO(g['objects.csv'].decode('latin1'))) if r and r[0].isdigit()}
    nifs = {r[0]: r for r in csv.reader(io.StringIO(g['items.csv'].decode('latin1'))) if r and r[0].isdigit()}
    pskins = {r[0].strip(): r for r in csv.reader(io.StringIO(g['pskins.csv'].decode('latin1'))) if r and r[0].strip().isdigit()}
    return objects, nifs, pskins


def apply_texture(g, tex):
    """objects.csv col 22 "Apply Texture" (a pskins.csv texture, items/pskins): the client paints it on the surface
    mapped by UV SET 2 (CLIENT MODDING GUIDE 13.7: emblem shields - sh_rounda has 3 UV sets; the guild emblem layers
    sit on sets 0 / 1 above it). Owner 2026-10-10: the round wooden shield drew as a white disc - the metal-rim sheet
    on set 0. With no guild emblem yet, the drawn surface is the applied texture on its own UVs."""
    g.setdefault('images', []).append({'uri': f'../textures/x4plus/{tex}.png'})
    g.setdefault('textures', []).append({'sampler': 0, 'source': len(g['images']) - 1})
    tex_index = len(g['textures']) - 1
    done = False
    for mesh in g.get('meshes', []):
        for prim in mesh.get('primitives', []):
            a = prim.get('attributes', {})
            if 'TEXCOORD_2' not in a or prim.get('material') is None:
                continue
            a['TEXCOORD_0'] = a['TEXCOORD_2']
            mat = g['materials'][prim['material']]
            mat.setdefault('pbrMetallicRoughness', {})['baseColorTexture'] = {'index': tex_index, 'texCoord': 0}
            done = True
    return done


# objects.csv rows the keep / relic sieges show (owner 2026-10-14): the six relics, the server's siege weapons
# (GameSiegeRam 2602 / Catapult 2598 / Trebuchet 2606 / Ballista 2645 / Cauldron 2607) and the other frontier siege rows
KEEP_MODELS = {630: 'Albion Relic Staff', 631: 'Albion Relic Scabbard', 632: 'Hibernian Relic Cauldron',
               633: 'Hibernian Relic Spear', 634: 'Norse Relic Hammer', 635: 'Norse Relic Horn',
               2598: 'Ranged Catapult', 2599: 'Frontiers Ranged Trebuchet', 2600: 'Light Siege Ram',
               2601: 'Medium Siege Ram', 2602: 'Heavy Siege Ram', 2604: 'Frontiers Scorpion', 2605: 'Frontiers Mini Ram',
               2606: 'Frontiers Mounted Trebuchet', 2607: 'Frontiers Boiling Oil', 2645: 'Frontiers Ranged Scorpion'}


# Custom weapons built by hand (CLAUDE VERSION tools/pet-art) whose art sits the other way round in its frame than the
# stock model it was cloned from: their grip as weapons.json "held" (held_frame's format: basis columns x, y, z, origin).
# 4834 Cairnbreaker (Dubh Sluagh mace, from the Dragonslayer hammer; owner 2026-10-16: "upside down completely ... a
# custom hammer model ... it has to be treated differently"): its grip roll, then end over end at the grip.
CUSTOM_GRIP = {}


def main():
    objects, nifs, pskins = tables()
    files = {p.name.lower(): p for p in (CLIENT / 'items').iterdir()}
    wanted = {}
    for src in ('items.json', 'merchants.json'):
        d = json.loads((ITEMS / src).read_text(encoding='utf-8'))
        for it in d.get('items', {}).values():
            if 0 < int(it.get('object_type', 0)) <= 42:
                wanted[str(it['model'])] = it['name']
    for m in (145, 636, 637):                               # gravestones (old server GameGravestone: Alb / Mid / Hib)
        wanted.setdefault(str(m), 'gravestone')
    loot = ROOT / 'godot/content/loot/loot.json'          # what monsters drop lies on the ground as its own model
    if loot.exists():
        for it in json.loads(loot.read_text(encoding='utf-8')).get('items', {}).values():
            if int(it.get('model') or 0) > 0:
                wanted.setdefault(str(it['model']), it['name'])
    wanted.setdefault('488', 'bag of coins')               # LootGeneratorMoney's money bag
    for m, nm in KEEP_MODELS.items():                      # keep / relic sieges (owner 2026-10-14)
        wanted.setdefault(str(m), nm)
    add_only = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--add=')), None)
    if add_only:
        # convert just these objects.csv models and merge them into weapons.json (a full run rewrites every model)
        wanted = {m.strip(): KEEP_MODELS.get(int(m), f'model {m}') for m in add_only.split(',') if m.strip().isdigit()}
    if '--server' in sys.argv:
        # 0.36c: every weapon / shield / instrument the shared server's items and NPCs can show (ItemTemplate,
        # ItemUnique - ROG, quest rewards, crafted - and NPCEquipment), read only
        import sqlite3
        db = ROOT.parent / 'new class test - CLAUDE VERSION/runtime/data/opendaoc.sqlite3.db'
        con = sqlite3.connect(db.as_uri() + '?mode=ro', uri=True)
        kinds = '(' + ','.join(str(t) for t in list(range(1, 32)) + [42, 45]) + ')'
        for table in ('ItemTemplate', 'ItemUnique'):
            for (m,) in con.execute(f'select distinct Model from {table} where Object_Type in {kinds} and Model > 0'):
                wanted.setdefault(str(m), f'server item {m}')
        for (m,) in con.execute('select distinct Model from NPCEquipment where Slot in (10, 11, 12, 13) and Model > 0'):
            wanted.setdefault(str(m), f'server npc weapon {m}')
        # the server's world objects (WorldObject: tents, campfires, crates, banners ... - drawn where the zone files
        # don't already have them baked) and anything lying on the ground
        for (m,) in con.execute('select distinct Model from WorldObject where Model > 0'):
            wanted.setdefault(str(m), f'server world object {m}')
        print(len(wanted), 'weapon / shield models wanted')
    for f in ((ROOT / 'godot/content/zones').glob('zone*/npcs.json') if not add_only else []):   # NPCs' weapons
        for rows in json.loads(f.read_text(encoding='utf-8')).get('equipment', {}).values():
            for r in rows:
                if int(r['slot']) in (10, 11, 12, 13) and int(r['model']) > 0:
                    wanted.setdefault(str(r['model']), f'npc weapon {r["model"]}')
    idx = TextureIndex()
    tex_dir = OUT / 'textures/original'
    tex_dir.mkdir(parents=True, exist_ok=True)
    out, missing = {}, []
    for model, item_name in sorted(wanted.items(), key=lambda kv: int(kv[0])):
        o = objects.get(model)
        if o is None or not o[2].strip().isdigit() or o[2].strip() not in nifs:
            missing.append((model, item_name, 'no objects/items.csv row'))
            continue
        n = nifs[o[2].strip()]
        nif = n[2].strip()
        path = files.get(nif.lower() + '.nif')
        if path is None:
            missing.append((model, item_name, nif + '.nif not in app/items'))
            continue
        apply = o[22].strip() if len(o) > 22 and o[22].strip().isdigit() and o[22].strip() != '0' else ''
        pr = pskins.get(apply) if apply else None
        folder = nif.lower() + (f'__p{apply}' if pr else '')    # one NIF, several applied textures (heater / tower)
        d = OUT / folder
        d.mkdir(parents=True, exist_ok=True)
        info = nif_static.convert(path.read_bytes(), str(d / 'model.gltf'), '../textures/x4plus')
        # shields: the client paints the base layer from the bearer's guild emblem colours (cloakpattern01, made at run
        # time) over a wood / metal detail layer; with no emblem, the base shows the detail texture itself
        g = json.loads((d / 'model.gltf').read_text(encoding='utf-8'))
        mats = g.get('extras', {}).get('nif_materials', [])
        changed = False
        for im in g.get('images', []):
            if 'cloakpattern' in im.get('uri', ''):
                det = next((m['slots']['detail']['tex'] for m in mats if m.get('slots', {}).get('base', {}).get('tex', '').startswith('cloakpattern')
                            and 'detail' in m.get('slots', {})), None)
                if det and det.endswith('__x2'):
                    det = det[:-4] + '__d2'                # drawn as the glTF's own base: the doubled copy (no shader x2)
                if det:
                    im['uri'] = f'../textures/x4plus/{det}.png'
                    info['textures'] = set(info['textures']) | {det}
                    changed = True
        if pr:
            tex = pr[2].strip().rsplit('.', 1)[0].lower()
            if apply_texture(g, tex):
                info['textures'] = set(info['textures']) | {tex}
                changed = True
        if changed:
            (d / 'model.gltf').write_text(json.dumps(g), encoding='utf-8')
        for t in sorted(info['textures']):
            doubled = t.endswith(('__d2', '__x2'))   # __x2: the raw detail map (detail_x2.py)                   # nif_static: a texture drawn at double brightness
            img = idx.image(t[:-4] if doubled else t)
            if img is None:
                if not t.startswith('cloakpattern'):       # the guild emblem slot: no emblem yet
                    missing.append((model, item_name, 'texture ' + t))
                continue
            if doubled and t.endswith('__d2'):
                import numpy as np
                from PIL import Image
                img = Image.fromarray(np.clip(np.asarray(img.convert('RGB'), np.float32) * 2.0, 0, 255).astype(np.uint8))
            save_if_changed(img, tex_dir / f'{t}.png')
        num = lambda v: int(v) if v.strip().lstrip('-').isdigit() else 0
        out[model] = {'nif': nif.lower(), 'file': f'{folder}/model.gltf', 'name': o[1],
                      'belt': num(o[17]), 'stance': num(o[19]), 'left': num(o[20]), 'back_offset': num(n[15]),
                      'sound_set': num(o[21]), 'shield': num(o[18])}   # cc_weapons.csv row: draw / swing / hit / parried sounds
        held = nif_static.held_frame(path.read_bytes())        # a mesh turned inside the NIF: its grip turns it back
        if not held and not out[model].get('shield'):           # a grip rolled about the length (shields: as checked)
            held = nif_static.held_roll(path.read_bytes())
        if model in CUSTOM_GRIP:
            held = CUSTOM_GRIP[model]
        if held:
            out[model]['held'] = held
    upscale_dir(tex_dir, OUT / 'textures/x4plus', factor_after=4)
    if add_only and (OUT / 'weapons.json').exists():
        old = json.loads((OUT / 'weapons.json').read_text(encoding='utf-8'))
        old['models'].update(out)
        out, missing = old['models'], old.get('missing', []) + missing
    (OUT / 'weapons.json').write_text(json.dumps({'models': out, 'missing': missing}, indent=1), encoding='utf-8')
    print(len(out), 'weapon models,', len(missing), 'missing:', missing[:10])


if __name__ == '__main__':
    main()
