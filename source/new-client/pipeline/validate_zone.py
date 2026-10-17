"""Automatic checks for a built zone, so a full-world import can be trusted without inspecting every object by hand.

    python validate_zone.py 200 [--top 25]

Reads godot/content/zones/zone<id> (written by build_zone.py) and reports:
  placement   objects whose base floats above or sinks below the terrain under their footprint
  water       objects standing in water that aren't water objects (docks, boats, bridges), and docks that don't
              reach out over the water (a check on the model orientation convention)
  materials   missing textures, converter warnings, texture layers that would render black
Writes godot/content/zones/zone<id>/validation.json and prints the worst cases first.
"""
import argparse, json, math, re, sys
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT

WATER_OBJECTS = re.compile(r'dock|pier|boat|bridge|ship|raft|buoy|lily|reed|kelp|water', re.I)


def gltf_positions(path):
    """Visible vertex positions (metres, model space) of a converted model, from its embedded buffer."""
    import base64
    doc = json.loads(Path(path).read_text())
    buf = base64.b64decode(doc['buffers'][0]['uri'].split(',', 1)[1])
    pts = []
    for node in doc['nodes']:
        if node['name'].startswith('collision_') or 'mesh' not in node:
            continue
        for prim in doc['meshes'][node['mesh']]['primitives']:
            acc = doc['accessors'][prim['attributes']['POSITION']]
            view = doc['bufferViews'][acc['bufferView']]
            arr = np.frombuffer(buf, dtype='<f4', count=acc['count'] * 3, offset=view['byteOffset'])
            pts.append(arr.reshape(-1, 3))
    return np.vstack(pts) if pts else np.zeros((0, 3))


class Terrain:
    def __init__(self, zdir, info):
        self.n = info['heights_2x_size']
        self.h = np.fromfile(zdir / info['heights_2x'], '<f4').reshape(self.n, self.n)
        self.cell = info['size_m'] / (self.n - 1)
        self.water = np.asarray(Image.open(zdir / info['water_mask']))
        self.size = info['size_m']
        self.levels = {b['id']: b['height'] for b in info['water']}

    def height(self, x, z):
        gx = np.clip(x / self.cell, 0, self.n - 1.001)
        gz = np.clip(z / self.cell, 0, self.n - 1.001)
        ix, iz = gx.astype(int), gz.astype(int)
        fx, fz = gx - ix, gz - iz
        h = self.h
        top = h[iz, ix] * (1 - fx) + h[iz, ix + 1] * fx
        bottom = h[iz + 1, ix] * (1 - fx) + h[iz + 1, ix + 1] * fx
        return top * (1 - fz) + bottom * fz

    def water_level(self, x, z):
        n = self.water.shape[0]
        ids = self.water[np.clip((z / self.size * n).astype(int), 0, n - 1), np.clip((x / self.size * n).astype(int), 0, n - 1)]
        return np.array([self.levels.get(int(i), -np.inf) for i in np.atleast_1d(ids)])


def footprint(pts, fixture):
    """World-space points of the model's base (lowest 0.4 m of its geometry) for one placement."""
    if not len(pts):
        return pts
    base = pts[pts[:, 1] <= pts[:, 1].min() + 0.4]
    a = math.radians(fixture['yaw'])
    s = fixture['scale']
    c, si = math.cos(a), math.sin(a)
    x = (base[:, 0] * c + base[:, 2] * si) * s          # Godot rotation about +Y
    z = (-base[:, 0] * si + base[:, 2] * c) * s
    px, py, pz = fixture['pos']
    return np.stack([x + px, base[:, 1] * s + py, z + pz], axis=1)


def check(zone_id, top):
    zdir = ROOT / f'godot/content/zones/zone{zone_id:03d}'
    info = json.loads((zdir / 'zone.json').read_text(encoding='utf-8'))
    terrain = Terrain(zdir, info)
    models = [gltf_positions(zdir / m['file']) for m in info['models']]
    placement, water, docks = [], [], []
    for f in info['fixtures']:
        m = info['models'][f['m']]
        fp = footprint(models[f['m']], f)
        if not len(fp):
            continue
        ground = terrain.height(fp[:, 0], fp[:, 2])
        gap = fp[:, 1] - ground                             # + floating, - buried
        lvl = terrain.water_level(fp[:, 0], fp[:, 2])
        wet = (lvl > ground) & (lvl > fp[:, 1] - 0.5)
        is_water_obj = bool(WATER_OBJECTS.search(m['name'] + ' ' + m['file']))
        size = float(np.ptp(models[f['m']][:, [0, 2]], axis=0).max() * f['scale'])
        rec = {'id': f['id'], 'name': f['name'], 'model': m['file'], 'daoc_xy': [round(f['pos'][0] / 0.025), round(f['pos'][2] / 0.025)],
               'size_m': round(size, 1), 'float_max_m': round(float(gap.max()), 2), 'float_median_m': round(float(np.median(gap)), 2),
               'buried_min_m': round(float(gap.min()), 2), 'wet_fraction': round(float(wet.mean()), 2)}
        # floating: most of the base clears the ground (a slope under one corner is normal for the original too)
        if np.median(gap) > 0.35 and not is_water_obj:
            placement.append(dict(rec, issue='floating'))
        elif np.median(gap) < -1.5 and size > 2.0:
            placement.append(dict(rec, issue='buried'))
        if wet.mean() > 0.5 and not is_water_obj and size > 1.0:
            water.append(dict(rec, issue='standing in water'))
        if re.search(r'dock|pier', m['name'], re.I):
            docks.append(dict(rec, issue='dock does not reach the water' if wet.mean() < 0.2 else 'ok'))
    textures_dir = zdir / 'textures/original'
    black = []
    for m in info['models']:
        doc = json.loads((zdir / m['file']).read_text())
        for spec in doc.get('extras', {}).get('nif_materials', []):
            for slot, v in spec.get('slots', {}).items():
                p = textures_dir / f"{v['tex']}.png"
                if not p.exists():
                    continue
                a = np.asarray(Image.open(p).convert('RGBA'), dtype=np.float32)
                # an opaque near-black multiply layer would blacken the surface it covers
                if slot in ('dark', 'detail') and a[..., 3].mean() > 200 and a[..., :3].mean() < 25:
                    black.append({'model': m['file'], 'slot': slot, 'texture': v['tex']})
    report = {'zone': info['name'], 'fixtures': len(info['fixtures']),
              'placement': sorted(placement, key=lambda r: -abs(r['float_median_m'])),
              'water': water, 'docks': docks, 'black_layers': black,
              'missing_textures': info.get('missing_textures', []), 'converter_warnings': info.get('warnings', [])}
    (zdir / 'validation.json').write_text(json.dumps(report, indent=1), encoding='utf-8')
    print(f"{info['name']}: {len(info['fixtures'])} fixtures checked")
    print(f"  placement issues {len(placement)}, standing in water {len(water)}, docks {[(d['issue']) for d in docks]}, "
          f"black layers {len(black)}, missing textures {len(report['missing_textures'])}, warnings {len(report['converter_warnings'])}")
    for r in report['placement'][:top]:
        print(f"   {r['issue']:9} {r['name'][:26]:26} at {r['daoc_xy']} median gap {r['float_median_m']:+.2f} m "
              f"(max {r['float_max_m']:+.2f}, min {r['buried_min_m']:+.2f}) size {r['size_m']} m")
    for r in water[:top]:
        print(f"   water     {r['name'][:26]:26} at {r['daoc_xy']} wet {r['wet_fraction']:.0%}")
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('zone', type=int)
    ap.add_argument('--top', type=int, default=25)
    a = ap.parse_args()
    check(a.zone, a.top)


if __name__ == '__main__':
    main()
