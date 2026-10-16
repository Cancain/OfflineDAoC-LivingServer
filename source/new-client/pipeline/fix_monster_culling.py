"""Sets each built monster model's materials one-sided or two-sided the way the client draws them
(nif_character.double_sided), without rebuilding the models (owner 2026-10-11: built double-sided, the wolf's mouth roof
showed through its forehead). Materials are matched to the NIF's shapes in the order nif_character.build writes them;
a model whose count doesn't match is reported and left alone. Run after any older build_monsters output."""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from assets_pipeline import CLIENT, ROOT
from netimmerse import read_nif, spec
import nif_character as nc
from build_monsters import find_figure, skinned_parts

OUT = ROOT / 'godot/content/monsters'


def sides_of(nif_name):
    sp = spec()
    nif = read_nif((CLIENT / 'figures' / nif_name).read_bytes())
    by_name = {b.get('name'): b for b in nif.blocks if b.type == 'NiNode'}
    out = []
    for part in skinned_parts(nif_name):
        node = by_name[part]
        for shape in [c for c in node.get('children') or [] if c is not None and sp.is_a(c.type, 'NiTriBasedGeom')]:
            data = shape['data']
            if not data.get('uv_sets'):
                continue
            out.append(nc.double_sided(shape, node))
    return out


def main():
    meta = json.loads((OUT / 'monsters.json').read_text())
    done, skipped, two = set(), [], 0
    for model, e in meta.items():
        gl = str(e.get('gltf', ''))
        if not gl.startswith('res://content/monsters/') or e.get('race') is not None:
            continue
        rel = gl[len('res://content/monsters/'):]
        if rel in done or rel.startswith('effects/'):
            continue
        done.add(rel)
        path = OUT / rel
        nif_name = find_figure(str(e.get('figure', '')))
        if nif_name is None or not path.exists():
            continue
        try:
            sides = sides_of(nif_name)
        except Exception as ex:
            skipped.append((rel, f'{type(ex).__name__}: {ex}'))
            continue
        g = json.loads(path.read_text(encoding='utf-8'))
        mats = g.get('materials', [])
        if len(mats) != len(sides):
            skipped.append((rel, f'{len(mats)} materials, {len(sides)} shapes'))
            continue
        changed = False
        for m, ds in zip(mats, sides):
            if bool(m.get('doubleSided')) != ds:
                m['doubleSided'] = ds
                changed = True
            two += int(ds)
        if changed:
            path.write_text(json.dumps(g, separators=(',', ':')), encoding='utf-8')
    print(len(done), 'models checked,', two, 'parts left two-sided,', len(skipped), 'skipped')
    for rel, why in skipped:
        print('  skipped', rel, '-', why)


if __name__ == '__main__':
    main()
