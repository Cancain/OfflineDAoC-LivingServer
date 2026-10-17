"""Re-export the built zones' models whose NIF has ladder 'climb' nodes (nif_static.climb_shapes -> hidden climb_<n>
meshes; owner 2026-10-10 ladders). A zone rebuild does the same.   python patch_climb_models.py"""
import re
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
import nif_static

sources = {}
for d in ('zones/Nifs', 'zones/Dnifs', 'frontiers/NIFS'):
    for p in (CLIENT / d).iterdir():
        sources.setdefault(p.name.lower(), p)
CLIMB = re.compile(rb'(?i)(?<![sS])climb')
done = 0
for zdir in sorted((ROOT / 'godot/content/zones').glob('zone[0-9][0-9][0-9]')):
    mdir = zdir / 'models'
    if not mdir.exists():
        continue
    local = {}
    zid = int(zdir.name[4:])
    for sub in (CLIENT / f'zones/zone{zid:03d}/nifs', CLIENT / f'frontiers/zones/zone{zid:03d}/nifs'):
        if sub.exists():
            local.update({p.name.lower(): p for p in sub.iterdir()})
    for g in sorted(mdir.glob('*.gltf')):
        base = g.stem.lower()
        if base.startswith(('item_', 'effect_')):
            continue
        src = local.get(base + '.npk') or sources.get(base + '.npk')
        if src is None:
            continue
        files = read_mpk(str(src))
        raw = next((v for k, v in files.items() if k.lower().endswith('.nif')), None)
        if raw is None or not CLIMB.search(raw):
            continue
        info = nif_static.convert(raw, str(g), '../textures/original')
        if info.get('climb_triangles'):
            done += 1
            print(zdir.name, base, info['climb_triangles'], 'climb triangles')
print(done, 'models re-exported')
