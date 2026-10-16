"""The roadside inns (bot plan phase 6, owner 2026-10-11) and the Horn of Rallying platforms beside them (phase 7 - the
look only; the horn does nothing yet).

One inn per realm, on the spot the owner marked on each zone map (checked flat and dry):
  Hibernia  Shannon Estuary (765, 415)  - the north road above Daingean Bridge, toward Connla
  Midgard   Myrkwood Forest (1209, 633) - just east of Galplen, toward Gna Faste
  Albion    Avalon Marsh (1240, 576)    - below the road east of Avalon, toward Caer Witrin (Adribard's Retreat nearby)
Everything is the client's own art, carried over from the realm's towns (owner rule: use client assets):
  - the realm's tavern (Hibernia's Elf Tavern from Mag Mell, Midgard's Norse Tavern from East Svealand, Albion's tavern
    from Camelot Hills), turned so its door faces the road; town props around the yard (carts, barrels, a well,
    fences, banners, a campfire); trees standing in the footprint cleared;
  - a dirt path painted in the ground splat from the door to the road (and to the horn platform), the yard trodden
    to dirt, the zone's grass clutter kept off the floor and the path;
  - NPCs: the realm's innkeeper (a new name and a look - model + outfit - no other NPC has), a realm healer inside
    (revives fallen companions for a fee), real guards copied from the town's own guards at the door and the road,
    a few level-15 adventurers (plain guard-style NPCs, owner: "if they die they die") walking out of the inn and up
    the road toward the town, idling, and back; the Horn Handler <Realm> by the horn;
  - the Horn of Rallying platform: the client's round Portal Platform with the realm's dressing (Hibernia a ring of
    standing stones, Midgard rune stones, Albion banners) and the Norse Relic Horn on it, scaled up;
  - monster spawns whose home is inside the inn grounds or on the platform move out to a ring just beyond (same
    monsters, levels and numbers - only where they stand; listed in content/companions/inns.json "moved");
  - content/companions/inns.json: the game's data (map labels, the NPCs' roles, the couriers, where things are).
Re-runnable: each zone's zone.json / npcs.json / splat / densemap are kept once in pipeline/inn_originals/ and every
run starts from those. After running: re-export the bot collision for the three zones (tools/export_world_collision.gd)
and drop their cached navigation (the script does both when --export is given).
    python place_inns.py [--export]
"""
import base64, json, math, re, shutil, subprocess, sys, uuid
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
import nif_static
from texture_index import TextureIndex

Z = ROOT / 'godot/content/zones'
ORIG = HERE / 'inn_originals'
OUT = ROOT / 'godot/content/companions/inns.json'
NS = uuid.UUID('6a0f2a52-7c61-4d39-9d0a-1b3f0d5e1a11')

TREE = re.compile(r'pine|elm|willow|tree|oak|birch|evergreen|bush|stump|log|fern|shrub|reed|lilly|cattail', re.I)

INNS = {
    'hib': dict(
        zone=202, site=(765.0, 415.0), town='Connla', town_at=(330.0, 640.0), realm=3,
        # the road from the inn down to Daingean Bridge, then west along the river toward Connla (read off the map)
        road_other=[(800, 400), (790, 300), (780, 200), (800, 100)],       # the road north (keep the horn off it)
        road_walk=[(800, 400), (752, 480), (688, 544), (648, 560), (560, 575), (480, 592), (400, 616), (340, 636)],
        building=dict(src=200, name='Elf Tavern', door=(-12.5, 0.0), door_dir=(-1.0, 0.0), floor=0.4, radius=15.0),
        # the innkeeper behind the bar (its top x 7.4..11.7, z -3.4..-2.5; the bottle shelf on the wall at z -6), facing
        # the room (owner 2026-10-11); the healer where Tavie stands in Mag Mell's own Elf Tavern
        inside=dict(innkeeper=(9.5, -4.6, 0.45), healer=(8.0, 4.8, 0.4), lounge=(-6.8, 5.2, 0.4)),
        innkeeper_face=(0.0, 1.0),
        props=[('Hib Cart', 200, (-17.0, 9.0), 30), ('crates and barrels', 200, (-16.0, -7.5), 0),
               ('Haystack', 200, (-19.0, -12.0), 15), ('Well', 200, (-22.0, 4.5), 0),
               ('campfire', 200, (-24.0, -5.0), 0)],
        path_layers=['h_soil', 'mud', 'h_tinypebbles'],
        innkeeper=dict(name='Muireann', look=(200, 'Aziliz'), outfit=(209, 'Selia')),   # a female elf (owner)
        wall_torches=dict(nif='phousing/nifs/int_wall_torch_01.NIF', side=2.2, height=2.3, scale=1.4),   # (owner)
        healer=dict(name='Ethniu', look=(202, 'Keagan'), outfit=(202, 'Kyle')),
        guard=(202, 'Guardian'),
        adventurers=['Cairbre', 'Saoirse', 'Oisin', 'Bebhinn'],
        adventurer_looks=[(202, 'Sentinel Grania'), (200, 'Kylirean'), (202, 'Dempsey'), (209, 'Selia')],
        horn=dict(dressing=[('Grave Ring Small', 207, 0.0, 0.0, 1.0)], handler_look=(202, 'Guardian'), guild='Hibernia'),
        courier=dict(model='631', name='a messenger fairy', fly=1.4),
    ),
    'mid': dict(
        zone=105, site=(1209.0, 633.0), town='Gna Faste', town_at=(880.0, 950.0), realm=2,
        # south-east from Galplen's road round the east shore of the lake toward Gna Faste
        road_other=[(1104, 608), (1150, 560), (1250, 450), (1350, 330)],   # Galplen and the road north-east
        road_walk=[(1176, 632), (1216, 672), (1312, 736), (1368, 832), (1328, 960), (1312, 1056), (1360, 1184),
                   (1328, 1264), (1184, 1272), (1040, 1256), (960, 1152), (912, 1024), (888, 944)],
        building=dict(src=101, name='Norse Tavern', door=(0.0, -20.6), door_dir=(0.0, -1.0), floor=0.7, radius=25.0),
        # the innkeeper behind the counter, where the barkeeps of East Svealand's and Haggerfel's own Norse Taverns
        # stand (6.6 / 6.0, -14.4), facing the room (owner 2026-10-11)
        inside=dict(innkeeper=(6.3, -14.35, 0.72), healer=(0.0, 9.3, 0.7), lounge=(3.3, -7.0, 0.8)),
        innkeeper_face=(-1.0, 0.0),
        road_guards=[(1189.98, 663.53), (1236.2, 669.18)],      # the owner's two spots (loc 47599 26541, 49448 26767)
        props=[('Cart', 101, (8.0, -27.0), 20), ('Merchant Cart', 101, (-9.0, -28.0), -15),
               ('Norse Fence', 101, (12.0, -23.5), 90), ('Norse Fence', 101, (-12.0, -23.5), 90),
               ('Fence Pole', 101, (12.0, -19.0), 0), ('campfire', 101, (9.0, -34.0), 0)],
        path_layers=['dirt1', 'stones', 'grassdry'],
        innkeeper=dict(name='Ragnfrid', look=(105, 'Barkeep Yseniver'), outfit=(120, 'Rana')),
        wall_torches=dict(nif='phousing/nifs/int_wall_torch_01.NIF', side=2.6, height=2.3, scale=1.4),   # (owner)
        healer=dict(name='Ingrith', look=(105, 'Hord'), outfit=(155, 'Klara Janson')),
        guard=(105, 'Troll Flayer'),
        adventurers=['Halvar', 'Gudrun', 'Bjarki', 'Sigrun'],
        adventurer_looks=[(105, 'Galena'), (151, 'Dalea Gronholm'), (101, 'Arnfinn'), (100, 'Linna')],
        horn=dict(dressing=[('Rune Stone', 105, 1.0, 45.0, 1.0), ('Rune Stone', 105, 1.0, 135.0, 1.0),
                            ('Rune Stone', 105, 1.0, 225.0, 1.0), ('Rune Stone', 105, 1.0, 315.0, 1.0)],
                  handler_look=(105, 'Sentry Crush'), guild='Midgard'),
        courier=dict(model='47', name='a messenger wolf', fly=0.0),
    ),
    'alb': dict(
        zone=9, site=(1240.0, 576.0), town='Caer Witrin', town_at=(500.0, 880.0), realm=1,
        # west along the road past the Avalon village and the bridge toward Caer Witrin
        road_other=[(1240, 528), (1280, 520), (1408, 528), (1500, 470), (1600, 400)],   # east toward Adribard's
        road_walk=[(1240, 528), (1184, 552), (1088, 624), (1008, 688), (960, 768), (848, 808), (790, 795), (704, 775),
                   (640, 784), (592, 848), (528, 930)],
        building=dict(src=0, name='Tavern', door=(0.3, -6.7), door_dir=(0.0, -1.0), floor=0.8, radius=16.0),
        # the innkeeper behind the counter, where the barkeeps of Camelot Hills' and Black Mountains South's own
        # Taverns stand (7.1 / 7.5, -0.2), facing the room (owner 2026-10-11)
        inside=dict(innkeeper=(7.3, -0.25, 0.8), healer=(0.3, 3.5, 0.8), lounge=(4.2, -1.8, 0.8)),
        innkeeper_face=(-1.0, 0.0),
        props=[('Well', 0, (-9.0, -15.0), 0), ('crates and barrels', 9, (10.0, -12.0), 0), ('sacks', 9, (11.5, -9.5), 30),
               ('Albion Banner', 9, (-6.0, -11.0), 180), ('Albion Banner', 9, (6.5, -11.0), 180),   # facing the road
               ('Fence1', 0, (13.0, -17.0), 90), ('Fence1', 0, (-14.0, -17.0), 90)],
        path_layers=['claymud', 'dirt1', 'smallstones'],
        innkeeper=dict(name='Goodwife Maude', look=(9, 'Sister Lilly'), outfit=(3, 'Heather Barclay')),   # a woman (owner 2026-10-11)
        # two wall torches either side of the door (owner 2026-10-11): the client's own (phousing int_wall_torch_01,
        # with its flame) - no 1.65 outdoor torch exists; 1.65 EXCEPTIONS MADE.txt
        wall_torches=dict(nif='phousing/nifs/int_wall_torch_01.NIF', side=2.2, height=2.3, scale=1.4),
        healer=dict(name='Brother Aldous', look=(26, 'Barkeep Broec'), outfit=(51, 'Lililah')),   # a man (owner 2026-10-11)
        guard=(9, 'Guardian Sergeant'),
        adventurers=['Edric', 'Rowena', 'Godwin', 'Isolde'],
        adventurer_looks=[(9, 'Armsman'), (51, 'Simone Innes'), (53, 'Bregusuid Dale'), (8, 'Eiddin Walelden')],
        horn=dict(dressing=[('Albion Banner', 9, 1.2, 45.0, 1.0), ('Albion Banner', 9, 1.2, 135.0, 1.0),
                            ('Albion Banner', 9, 1.2, 225.0, 1.0), ('Albion Banner', 9, 1.2, 315.0, 1.0)],
                  handler_look=(9, 'Guardian Sergeant'), guild='Albion'),
        courier=dict(model='912', name='a glowing sphere', fly=1.6),
    ),
}
PLATFORM = {'hib': 207, 'mid': 111, 'alb': 11}       # the realm's own Portal Platform copy
PLAT_SCALE = 0.55                                    # the portal pad is 24 m across: about 13 m here
HORN_LEN = 4.0                                       # metres
CLEAR_INN = 55.0                                     # monster homes inside this of the inn move out
CLEAR_HORN = 22.0
RING = (58.0, 76.0)
ADV_LEVEL = 15
ROAD_WALK_MAX = 650.0                                # how far up the road the adventurers walk (toward the town)


# ---------------------------------------------------------------- helpers

def load_json(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))


def save_json(p, d, indent=None):
    Path(p).write_text(json.dumps(d, indent=indent), encoding='utf-8')


def originals(zid):
    """The zone's untouched files, kept once; every run starts from them."""
    zd = Z / f'zone{zid:03d}'
    od = ORIG / f'zone{zid:03d}'
    if not od.exists():
        od.mkdir(parents=True)
        for f in ['zone.json', 'npcs.json', 'densemap.png']:
            shutil.copy2(zd / f, od / f)
        shutil.copytree(zd / 'splat', od / 'splat')
    for f in HEIGHT_FILES:                                 # (kept from the first run that flattened the ground)
        if not (od / f).exists() and (zd / f).exists():
            shutil.copy2(zd / f, od / f)
    for f in ['zone.json', 'npcs.json', 'densemap.png'] + [f for f in HEIGHT_FILES if (od / f).exists()]:
        shutil.copy2(od / f, zd / f)
    shutil.rmtree(zd / 'splat')
    shutil.copytree(od / 'splat', zd / 'splat')


HEIGHT_FILES = ['heights.f32', 'heights_2x.f32', 'heights_2x_apron.f32']


class Ground:
    """The ground as the game draws it: the 513-sample refined grid (the 257 grid under-read the drawn ground, owner
    2026-10-11: crates and barrels floating). flatten() levels it under a building as the client's own terrain is
    under every placed building (Mag Mell's Elf Tavern: flat at its base, to the centimetre), in all three grids."""
    def __init__(self, zid, zone):
        self.zd = Z / f'zone{zid:03d}'
        self.size = zone['size_m']
        self.grids = {}
        for f, n, off in (('heights.f32', 257, 0), ('heights_2x.f32', 513, 0), ('heights_2x_apron.f32', 515, 1)):
            if (self.zd / f).exists():
                self.grids[f] = (np.fromfile(self.zd / f, dtype='<f4').reshape(n, n).copy(), n, off)
        self.H, hs, _ = self.grids['heights_2x.f32']
        self.hs, self.cell = hs, self.size / (hs - 1)
        self.dirty = False

    def flatten(self, cx, cz, a, mn, mx, y, blend=4.0):
        """Level the ground to y inside a building's rotated footprint (local x mn[0]..mx[0], z mn[2]..mx[2]),
        easing back to the old ground over `blend` metres outside it."""
        for f, (G, n, off) in self.grids.items():
            cell = self.size / ((n - off * 2) - 1)
            r = math.hypot(max(abs(mn[0]), abs(mx[0])), max(abs(mn[2]), abs(mx[2]))) + blend
            i0, i1 = int((cx - r) / cell) + off, int((cx + r) / cell) + off + 1
            j0, j1 = int((cz - r) / cell) + off, int((cz + r) / cell) + off + 1
            for j in range(max(j0, 0), min(j1, n - 1) + 1):
                for i in range(max(i0, 0), min(i1, n - 1) + 1):
                    wx, wz = (i - off) * cell - cx, (j - off) * cell - cz
                    lx = wx * math.cos(a) - wz * math.sin(a)        # world -> building-local (inverse of rot)
                    lz = wx * math.sin(a) + wz * math.cos(a)
                    ox = max(mn[0] - lx, 0.0, lx - mx[0])
                    oz = max(mn[2] - lz, 0.0, lz - mx[2])
                    d = math.hypot(ox, oz)
                    if d >= blend:
                        continue
                    t = d / blend
                    t = t * t * (3 - 2 * t)                       # smooth ease back to the old ground
                    G[j, i] = y * (1 - t) + G[j, i] * t
        self.dirty = True

    def save(self):
        if self.dirty:
            for f, (G, n, off) in self.grids.items():
                G.astype('<f4').tofile(self.zd / f)

    def footprint_median(self, x, z, a, mn, mx):
        pts = [(lx, lz) for lx in np.linspace(mn[0], mx[0], 4) for lz in np.linspace(mn[2], mx[2], 4)]
        return float(np.median([self.h(x + rot(a, lx, lz)[0], z + rot(a, lx, lz)[1]) for lx, lz in pts]))

    def footprint_min(self, x, z, a, mn, mx):
        """The lowest drawn ground under a prop's rotated footprint (its corners and middle): set there, no edge of it
        hangs in the air on a slope (it sinks a little into the higher side instead, as placed objects do)."""
        pts = [(lx, lz) for lx in (mn[0], 0.0, mx[0]) for lz in (mn[2], 0.0, mx[2])]
        return min(self.h(x + rot(a, lx, lz)[0], z + rot(a, lx, lz)[1]) for lx, lz in pts)

    def h(self, x, z):
        gx = min(max(x / self.cell, 0.0), self.hs - 1.001)
        gz = min(max(z / self.cell, 0.0), self.hs - 1.001)
        ix, iz = int(gx), int(gz)
        fx, fz = gx - ix, gz - iz
        H = self.H
        return float((H[iz, ix] * (1 - fx) + H[iz, ix + 1] * fx) * (1 - fz) + (H[iz + 1, ix] * (1 - fx) + H[iz + 1, ix + 1] * fx) * fz)


def rot(a, lx, lz):
    """A building-local x / z by the fixture's yaw a (radians) - Godot's Basis(UP, a)."""
    return lx * math.cos(a) + lz * math.sin(a), -lx * math.sin(a) + lz * math.cos(a)


def heading_to(dx, dz):
    """DAoC heading (0..4095) for an NPC facing world direction dx, dz (its model faces +Z; yaw = -heading)."""
    yaw = math.atan2(dx, dz)
    return int(round(-yaw * 4096 / (2 * math.pi))) % 4096


def road_mask(zid, zone):
    m = load_json(ROOT / 'godot/content/maps/maps.json')['zones'][str(zid)]
    size = int(zone['size_m'])
    mp = np.array(Image.open(ROOT / 'godot/content/maps/x4plus' / m['map']).convert('RGB').resize((size, size))).astype(int)
    return (mp[:, :, 0] > 140) & (mp[:, :, 1] < 70) & (mp[:, :, 2] < 70)


def nearest_road(mask, x, z):
    ry, rx = np.nonzero(mask)
    d = (rx - x) ** 2 + (ry - z) ** 2
    i = int(d.argmin())
    return float(rx[i]), float(ry[i]), math.sqrt(float(d[i]))


def road_route(mask, start, goal, max_len):
    """Along the painted road from start toward goal (a breadth-first walk over the road pixels, 1 m each, the map's
    labels bridged by a 3 m dilation); cut at max_len metres. Points every ~10 m."""
    from collections import deque
    m = mask.copy()
    for _ in range(3):
        m = m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    h, w = m.shape
    sx, sz = int(start[0]), int(start[1])
    ry, rx = np.nonzero(m)
    gi = int(((rx - goal[0]) ** 2 + (ry - goal[1]) ** 2).argmin())
    gx, gz = int(rx[gi]), int(ry[gi])
    prev = -np.ones((h, w), dtype=np.int64)
    q = deque([(sx, sz)])
    prev[sz, sx] = sz * w + sx
    while q:
        x, z = q.popleft()
        if (x, z) == (gx, gz):
            break
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, nz = x + dx, z + dz
            if 0 <= nx < w and 0 <= nz < h and m[nz, nx] and prev[nz, nx] < 0:
                prev[nz, nx] = z * w + x
                q.append((nx, nz))
    if prev[gz, gx] < 0:
        return [start, goal]
    pts = []
    c = gz * w + gx
    while True:
        pts.append((c % w, c // w))
        p = int(prev[c // w, c % w])
        if p == c:
            break
        c = p
    pts.reverse()
    out, walked, last = [pts[0]], 0.0, pts[0]
    for p in pts[1:]:
        walked += math.hypot(p[0] - last[0], p[1] - last[1])
        last = p
        if math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) >= 10.0:
            out.append(p)
        if walked >= max_len:
            break
    return [(float(x), float(z)) for x, z in out]


def walk_route(pts, max_len):
    """Hand-laid road waypoints, a point every ~10 m, cut at max_len metres."""
    out, walked = [pts[0]], 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(seg / 10))
        for i in range(1, n + 1):
            p = (a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)
            walked += seg / n
            out.append((float(p[0]), float(p[1])))
            if walked >= max_len:
                return out
    return out


def gltf_bounds(path):
    """Bounding box of a glTF's positions (node transforms ignored: zone models are flat-baked)."""
    g = load_json(path)
    mn, mx = np.full(3, 1e9), np.full(3, -1e9)
    pos = {p['attributes']['POSITION'] for m in g['meshes'] for p in m['primitives'] if 'POSITION' in p['attributes']}
    for i in pos:                                       # positions only (the normals' +-1 made the horn float)
        a = g['accessors'][i]
        if 'min' in a and 'max' in a:
            mn = np.minimum(mn, a['min'])
            mx = np.maximum(mx, a['max'])
    return mn, mx


def gltf_points(path):
    """Every vertex position of a glTF (zone models are flat-baked: no node transforms)."""
    import base64
    g = load_json(path)
    bufs = []
    for b in g['buffers']:
        u = b['uri']
        bufs.append(base64.b64decode(u.split(',', 1)[1]) if u.startswith('data:') else (Path(path).parent / u).read_bytes())
    out = []
    for i in {p['attributes']['POSITION'] for m in g['meshes'] for p in m['primitives'] if 'POSITION' in p['attributes']}:
        a = g['accessors'][i]
        bv = g['bufferViews'][a['bufferView']]
        out.append(np.frombuffer(bufs[bv['buffer']], dtype=np.float32, count=a['count'] * 3,
                                 offset=bv.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, 3))
    return np.concatenate(out) if out else np.zeros((0, 3), np.float32)


def horn_spot(zone, zd, cx, top, cz, prad, hyaw):
    """Where the horn lies on the platform: of spots round it (at 55% of its radius), the one nearest the road side
    with nothing of the platform or its dressing standing over 0.3 m above the top within 0.9 m of the horn's length
    (4 m, lying along the ring). Returns x, z and its yaw."""
    solid = []
    for f in zone['fixtures']:
        if f.get('source') != 'inn' or f['name'] == 'Horn of Rallying' or math.hypot(f['pos'][0] - cx, f['pos'][2] - cz) > prad + 3:
            continue
        p = gltf_points(zd / zone['models'][f['m']]['file']) * float(f.get('scale', 1.0))
        a = math.radians(f['yaw'])
        wx = p[:, 0] * math.cos(a) + p[:, 2] * math.sin(a) + f['pos'][0]
        wz = -p[:, 0] * math.sin(a) + p[:, 2] * math.cos(a) + f['pos'][2]
        keep = p[:, 1] + f['pos'][1] > top + 0.3
        solid.append(np.stack([wx[keep], wz[keep]], 1))
    solid = np.concatenate(solid) if solid else np.zeros((0, 2))
    r = prad * 0.55
    for k in range(24):
        ang = math.radians(hyaw) + math.pi / 12 * ((k + 1) // 2) * (1 if k % 2 else -1)
        px, pz = cx + r * math.sin(ang), cz + r * math.cos(ang)
        tx, tz = math.cos(ang), -math.sin(ang)             # along the ring
        clear = True
        if len(solid):
            for t in (-2.0, -1.0, 0.0, 1.0, 2.0):
                qx, qz = px + tx * t, pz + tz * t
                if np.min(np.hypot(solid[:, 0] - qx, solid[:, 1] - qz)) < 0.9:
                    clear = False
                    break
        if clear:
            return px, pz, math.degrees(math.atan2(tx, tz))
    print('WARNING no clear spot for the horn on the platform - left in the middle')
    return cx, cz, hyaw + 90.0


def _reach(sz_, src, f):
    """How far round a placed object its lights count as its own: half its size (at least 4 m), plus a metre."""
    mn, mx = gltf_bounds(Z / f'zone{src:03d}' / sz_['models'][f['m']]['file'])
    return max(float(max(mx[0] - mn[0], mx[2] - mn[2])) / 2 * float(f.get('scale', 1.0)), 4.0) + 1.0


def _lights_near(sz_, f, reach=5.0):
    return any(math.hypot(l['pos'][0] - f['pos'][0], l['pos'][2] - f['pos'][2]) <= reach for l in sz_.get('lights', []))


def lights_from(zone, src, name, x, y, z, a):
    """The client's own point lights (lights.csv) at the source placement of a copied building or prop - the tavern's
    glow, a campfire's fire light - placed the same way at the copy."""
    of = ORIG / f'zone{src:03d}/zone.json'
    sz_ = load_json(of if of.exists() else Z / f'zone{src:03d}/zone.json')
    m = next((i for i, mm in enumerate(sz_['models']) if mm['name'] == name), None)
    f = next((f for f in sz_['fixtures'] if f['m'] == m and f.get('source') != 'inn'), None) if m is not None else None
    if f is None or not _lights_near(sz_, f, _reach(sz_, src, f)):
        # a world object (the server's campfire is a 'wardnode' with no light of its own): the client's own model of
        # that name and its light - every client Campfire has its fire light (lights.csv 'fire-light')
        for alt in (name.title(), name.capitalize()):
            m = next((i for i, mm in enumerate(sz_['models']) if mm['name'] == alt), None)
            cands = [f2 for f2 in sz_['fixtures'] if f2['m'] == m and f2.get('source') != 'inn'] if m is not None else []
            f = next((f2 for f2 in cands if _lights_near(sz_, f2, _reach(sz_, src, f2))), None)
            if f is not None:
                break
    if f is None:
        return
    fx, fy, fz = f['pos']
    fa = math.radians(f['yaw'])
    reach = _reach(sz_, src, f)
    for l in sz_.get('lights', []):
        dx, dz = l['pos'][0] - fx, l['pos'][2] - fz
        if math.hypot(dx, dz) > reach:
            continue
        lx = dx * math.cos(fa) - dz * math.sin(fa)
        lz = dx * math.sin(fa) + dz * math.cos(fa)
        wx, wz = rot(a, lx, lz)
        nl = dict(l)
        nl['pos'] = [x + wx, y + (l['pos'][1] - fy), z + wz]
        nl['source'] = 'inn'
        zone.setdefault('lights', []).append(nl)


_TEX_CACHE = {}


def texture_names(g):
    """Every texture a glTF names: its images and the names in its materials' / nodes' extras (NifMaterials loads
    those by name from textures/<set>/<name>.png)."""
    if not _TEX_CACHE:
        for f in Z.glob('zone*/textures/original/*.png'):
            _TEX_CACHE[f.stem.lower()] = f.name
    out = set()
    def walk(v):
        if isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, str) and not v.startswith('data:') and len(v) < 120:
            stem = Path(v).stem.lower()
            if stem in _TEX_CACHE:
                out.add(_TEX_CACHE[stem])
    walk({k: v for k, v in g.items() if k not in ('buffers', 'accessors', 'bufferViews')})
    return out


def copy_model(src_zid, name, dst_zid, zone):
    """The model named `name` from zone src into zone dst (its glTF and its textures, both sets); returns its index."""
    src = load_json(Z / f'zone{src_zid:03d}/zone.json')
    m = next((m for m in src['models'] if m['name'] == name), None)
    if m is None:                                       # a world object's prop: named by its fixture
        f = next(f for f in src['fixtures'] if f.get('name') == name)
        m = src['models'][f['m']]
    for i, mm in enumerate(zone['models']):
        if mm['file'] == m['file'] and mm['name'] == m['name']:
            return i
    sd, dd = Z / f'zone{src_zid:03d}', Z / f'zone{dst_zid:03d}'
    if not (dd / m['file']).exists():
        shutil.copy2(sd / m['file'], dd / m['file'])
    for tex in texture_names(load_json(sd / m['file'])):
        for tset in ('original', 'x4plus'):
            d = dd / 'textures' / tset / tex
            if d.exists():
                continue
            # the source zone's copy, else any zone's (effects and props name textures their own zone may lack)
            src_file = sd / 'textures' / tset / tex
            if not src_file.exists():
                src_file = next(iter(Z.glob(f'zone*/textures/{tset}/{tex}')), None)
            if src_file is not None and src_file.exists():
                d.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src_file, d)
    zone['models'].append(dict(m))
    return len(zone['models']) - 1


def client_nif_model(dst_zid, zone, rel, name):
    """A client NIF (by its path under the client folder) as a zone model with its textures; its index."""
    for i, m in enumerate(zone['models']):
        if m['name'] == name:
            return i
    dd = Z / f'zone{dst_zid:03d}'
    src = CLIENT / rel
    stem = Path(rel).stem.lower()
    info = nif_static.convert(src.read_bytes(), str(dd / f'models/client_{stem}.gltf'), '../textures/original')
    idx = TextureIndex()
    for n in info['textures']:
        img = idx.image(n)
        if img is not None:
            img.save(dd / 'textures/original' / f'{n}.png')
    zone['models'].append({'nif': rel.rsplit('.', 1)[0].lower(), 'name': name, 'file': f'models/client_{stem}.gltf',
                           'triangles': info['triangles'], 'collision_triangles': info['collision_triangles'], 'warnings': []})
    return len(zone['models']) - 1


def horn_model(dst_zid, zone):
    """The Norse Relic Horn (items/R_NHorn.nif) as a zone model."""
    for i, m in enumerate(zone['models']):
        if m['name'] == 'Horn of Rallying':
            return i
    dd = Z / f'zone{dst_zid:03d}'
    raw = next(p for p in (CLIENT / 'items').iterdir() if p.name.lower() == 'r_nhorn.nif').read_bytes()
    info = nif_static.convert(raw, str(dd / 'models/item_r_nhorn.gltf'), '../textures/original')
    idx = TextureIndex()
    for n in info['textures']:
        img = idx.image(n)
        if img is not None:
            img.save(dd / 'textures/original' / f'{n}.png')
    zone['models'].append({'nif': 'items/r_nhorn', 'name': 'Horn of Rallying', 'file': 'models/item_r_nhorn.gltf',
                           'triangles': info['triangles'], 'collision_triangles': info['collision_triangles'], 'warnings': []})
    return len(zone['models']) - 1


def place(zone, m, name, x, y, z, yaw_deg, scale=1.0, collide=True):
    fid = max([int(f.get('id', -1)) for f in zone['fixtures']] + [0]) + 1
    f = {'m': m, 'name': name, 'pos': [x, y, z], 'yaw': yaw_deg, 'scale': scale, 'collide': collide, 'id': fid,
         'source': 'inn'}
    if not collide:
        f['no_collision'] = True
    zone['fixtures'].append(f)
    return f


def spawn_of(zid, name):
    sp = load_json(Z / f'zone{zid:03d}/npcs.json')
    s = next(s for s in sp['spawns'] if s['name'] == name)
    return s, sp.get('equipment', {})


def new_spawn(tmpl, uid, **over):
    s = json.loads(json.dumps(tmpl))
    s.update({'id': str(uuid.uuid5(NS, uid)), 'roam': 0, 'trains': None, 'items': '', 'faction': 0, 'inn': True})
    s.update(over)
    if 'level' in over:
        s['levels'] = [over['level']]
    if 'model' in over:
        s['models'] = [over['model']]
    return s


def paint_disc(layers_by_patch, zone, zid, ground_layer_names, x, z, r):
    """Dirt in the splat: the path layer full, the layers above it cleared, inside radius r (soft 1.5 m edge)."""
    P = zone['size_m'] / 8.0
    for cx in range(int((x - r) // P), int((x + r) // P) + 1):
        for cz in range(int((z - r) // P), int((z + r) // P) + 1):
            key = f'{cx}_{cz}'
            patch = zone['ground_splat']['patches'].get(key)
            if not patch:
                continue
            names = [l['tex'].lower() for l in patch['layers']]
            li = next((names.index(n) for n in ground_layer_names if n in names and names.index(n) > 0), -1)
            if li < 0:
                continue
            if key not in layers_by_patch:
                ws = [np.array(Image.open(Z / f'zone{zid:03d}' / w).convert('RGBA')).astype(np.float32) for w in patch['weights']]
                layers_by_patch[key] = (patch, ws)
            _, ws = layers_by_patch[key]
            n = ws[0].shape[0]
            px = P / n
            for v in range(n):
                wz = cz * P + (v + 0.5) * px
                if abs(wz - z) > r + 2:
                    continue
                for u in range(n):
                    wx = cx * P + (u + 0.5) * px
                    d = math.hypot(wx - x, wz - z)
                    if d > r + 1.5:
                        continue
                    k = 1.0 if d <= r else 1.0 - (d - r) / 1.5
                    for L in range(1, len(patch['layers'])):
                        i = L - 1
                        img, ch = ws[0 if i < 4 else 1], i % 4
                        if L == li:
                            img[v, u, ch] = max(img[v, u, ch], 255.0 * k)
                        elif L > li and patch['layers'][L].get('tileable', True):
                            img[v, u, ch] *= 1.0 - k


def paint_line(lbp, zone, zid, names, a, b, width):
    n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 1.2))
    for i in range(n + 1):
        t = i / n
        paint_disc(lbp, zone, zid, names, a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, width / 2)


def clear_clutter(dense, size, x, z, r):
    n = dense.shape[0]
    c = size / n
    for v in range(max(0, int((z - r) / c)), min(n, int((z + r) / c) + 1)):
        for u in range(max(0, int((x - r) / c)), min(n, int((x + r) / c) + 1)):
            if math.hypot((u + 0.5) * c - x, (v + 0.5) * c - z) <= r + c * 0.5:
                dense[v, u] = 0


class Footprint:
    """A placed building's rotated outline (local x mn[0]..mx[0], z mn[2]..mx[2]): paths and routes keep off it."""
    def __init__(self, cx, cz, a, mn, mx):
        self.cx, self.cz, self.a, self.mn, self.mx = cx, cz, a, mn, mx

    def out_d(self, x, z):
        wx, wz = x - self.cx, z - self.cz
        lx = wx * math.cos(self.a) - wz * math.sin(self.a)
        lz = wx * math.sin(self.a) + wz * math.cos(self.a)
        return math.hypot(max(self.mn[0] - lx, 0.0, lx - self.mx[0]), max(self.mn[2] - lz, 0.0, lz - self.mx[2]))

    def hits(self, p, q, margin):
        n = max(2, int(math.hypot(q[0] - p[0], q[1] - p[1])))
        return any(self.out_d(p[0] + (q[0] - p[0]) * i / n, p[1] + (q[1] - p[1]) * i / n) < margin for i in range(n + 1))

    def corners(self, margin):
        out = []
        for lx in (self.mn[0] - margin, self.mx[0] + margin):
            for lz in (self.mn[2] - margin, self.mx[2] + margin):
                wx, wz = rot(self.a, lx, lz)
                out.append((self.cx + wx, self.cz + wz))
        return out

    def detour(self, p, q, margin=2.0):
        """p -> q with corner waypoints between when the straight line would cross the building."""
        if not self.hits(p, q, margin):
            return [p, q]
        cs = self.corners(margin + 1.5)
        best = None
        for c in cs:
            if not self.hits(p, c, margin) and not self.hits(c, q, margin):
                d = math.dist(p, c) + math.dist(c, q)
                if best is None or d < best[0]:
                    best = (d, [p, c, q])
        if best is None:                                   # round two corners
            for c1 in cs:
                for c2 in cs:
                    if c1 != c2 and not self.hits(p, c1, margin) and not self.hits(c1, c2, margin) and not self.hits(c2, q, margin):
                        d = math.dist(p, c1) + math.dist(c1, c2) + math.dist(c2, q)
                        if best is None or d < best[0]:
                            best = (d, [p, c1, c2, q])
        return best[1] if best else [p, q]


def on_road(roads, pts, reach=8.0):
    """Each point moved onto the painted road when one is within reach (routes follow its bends instead of cutting
    across the woods between hand-laid points - owner 2026-10-11)."""
    ry, rx = np.nonzero(roads)
    out = []
    for x, z in pts:
        d = (rx - x) ** 2 + (ry - z) ** 2
        i = int(d.argmin())
        out.append((float(rx[i]), float(ry[i])) if d[i] <= reach * reach else (x, z))
    return out


def flat_spot(g, wet, x0, z0, rmin, rmax, avoid, radius, roads=None, road_gap=0.0, ok=None):
    best = None
    ry, rx = np.nonzero(roads) if roads is not None else (np.array([]), np.array([]))
    for r in np.arange(rmin, rmax + 0.1, 2.0):
        for a in np.arange(0, 360, 6):
            x, z = x0 + r * math.cos(math.radians(a)), z0 + r * math.sin(math.radians(a))
            if any(math.hypot(x - ax, z - az) < ar for ax, az, ar in avoid):
                continue
            if ok is not None and not ok(x, z):
                continue
            if len(rx) and ((rx - x) ** 2 + (ry - z) ** 2).min() < road_gap * road_gap:
                continue                                   # clear of the whole road, not one point of it
            hs = [g.h(x + dx, z + dz) for dx in np.arange(-radius, radius + 0.1, radius / 2) for dz in np.arange(-radius, radius + 0.1, radius / 2)]
            if any(wet(x + dx, z + dz, min(hs)) for dx in (-radius, 0, radius) for dz in (-radius, 0, radius)):
                continue
            s = max(hs) - min(hs) + r * 0.01
            if best is None or s < best[0]:
                best = (s, float(x), float(z), max(hs))
    return best


# ---------------------------------------------------------------- one inn

def build_inn(key, spec, all_names):
    zid = spec['zone']
    originals(zid)
    zd = Z / f'zone{zid:03d}'
    zone = load_json(zd / 'zone.json')
    npcs = load_json(zd / 'npcs.json')
    g = Ground(zid, zone)
    W = np.array(Image.open(zd / zone['water_mask']))
    water_h = {int(w['id']): float(w.get('height', -1e9)) for w in zone.get('water', [])}

    def wet(x, z, ground):                                 # under its own water body's surface (the mask spans more)
        v = W[min(max(int(z / g.size * W.shape[0]), 0), W.shape[0] - 1), min(max(int(x / g.size * W.shape[1]), 0), W.shape[1] - 1)]
        return v != 255 and ground < water_h.get(int(v), -1e9) + 0.6

    roads = road_mask(zid, zone)
    sx, sz = spec['site']
    rx, rz, rd = nearest_road(roads, sx, sz)
    D = ((rx - sx) / rd, (rz - sz) / rd)                   # toward the road
    b = spec['building']
    ddx, ddz = b['door_dir']
    a = math.atan2(D[1], -D[0]) if ddx < 0 else math.atan2(-D[0], -D[1])
    yaw = math.degrees(a)
    foot = [g.h(sx + dx, sz + dz) for dx in np.arange(-b['radius'] * 0.8, b['radius'] * 0.81, 3) for dz in np.arange(-b['radius'] * 0.8, b['radius'] * 0.81, 3)]
    by = float(np.median(foot)) - 0.1
    report = {'zone': zid, 'site': [sx, sz], 'yaw': yaw, 'ground': [min(foot), max(foot)], 'road_m': rd}

    # clear trees standing in the footprint and the yard
    door_l = b['door']
    dwx, dwz = rot(a, *door_l)
    door = (sx + dwx, sz + dwz)
    out_x, out_z = rot(a, ddx, ddz)
    yard = (door[0] + out_x * 6.0, door[1] + out_z * 6.0)
    removed = []
    keep = []
    tmn, tmx = gltf_bounds(Z / f'zone{b["src"]:03d}' / next(mm['file'] for mm in load_json(Z / f'zone{b["src"]:03d}/zone.json')['models'] if mm['name'] == b['name']))
    for f in zone['fixtures']:
        fx, fz = f['pos'][0], f['pos'][2]
        # within 6 m of the building's real outline (a canopy reaches that far - owner 2026-10-11: a willow through
        # Albion's upper floor; its tavern reaches 18.5 m out on one side, past the old radius)
        wx_, wz_ = fx - sx, fz - sz
        lx_, lz_ = wx_ * math.cos(a) - wz_ * math.sin(a), wx_ * math.sin(a) + wz_ * math.cos(a)
        out_d = math.hypot(max(tmn[0] - lx_, 0.0, lx_ - tmx[0]), max(tmn[2] - lz_, 0.0, lz_ - tmx[2]))
        inside = out_d < 6.0 or math.hypot(fx - sx, fz - sz) < b['radius'] + 3 or math.hypot(fx - yard[0], fz - yard[1]) < 12
        if inside and TREE.search(f.get('name', '')):
            removed.append(f['name'])
            continue
        keep.append(f)
    zone['fixtures'] = keep
    report['trees_cleared'] = len(removed)

    # the tavern, and the town props around the yard
    m = copy_model(b['src'], b['name'], zid, zone)
    place(zone, m, 'Roadside Inn', sx, by, sz, yaw)
    bmn, bmx = gltf_bounds(zd / zone['models'][m]['file'])
    fp = Footprint(sx, sz, a, bmn, bmx)
    rx, rz, rd = nearest_road(roads, *yard)                # the road the yard leads to
    g.flatten(sx, sz, a, bmn, bmx, by)                     # the ground under it level with its base (no grass inside)
    wt = spec.get('wall_torches')
    if wt:
        ti = client_nif_model(zid, zone, wt['nif'], 'Wall Torch')
        ox_, oz_ = rot(a, ddx, ddz)                         # out of the door's wall
        for side in (-1.0, 1.0):
            lx_ = door_l[0] + side * wt['side'] * (1.0 if abs(ddz) > abs(ddx) else 0.0)
            lz_ = door_l[1] + side * wt['side'] * (1.0 if abs(ddx) > abs(ddz) else 0.0)
            wx_, wz_ = rot(a, lx_, lz_)
            tx, tz = sx + wx_ + ox_ * 0.05, sz + wz_ + oz_ * 0.05
            ty = by + b['floor'] + wt['height']
            place(zone, ti, 'Wall Torch', tx, ty, tz, math.degrees(math.atan2(ox_, oz_)), wt['scale'], collide=False)
            zone.setdefault('lights', []).append({'pos': [tx + ox_ * 0.5, ty + 0.5, tz + oz_ * 0.5], 'type': 9,
                                                  'name': 'fire-light', 'color': [1.0, 0.39215686274509803, 0.0],
                                                  'range_m': 5.0, 'source': 'inn'})
    for k_, spot in enumerate(('innkeeper', 'lounge')):
        lx_, lz_, fy_ = spec['inside'][spot]
        wx_, wz_ = rot(a, lx_, lz_)
        zone.setdefault('lights', []).append({'pos': [sx + wx_, by + fy_ + 2.4, sz + wz_], 'type': 3, 'name': 'orange light',
                                              'color': [1.0, 0.6666666666666666, 0.2549019607843137], 'range_m': 7.5,
                                              'source': 'inn'})
    lights_from(zone, b['src'], b['name'], sx, by, sz, a)
    for name, src, (lx, lz), py in spec['props']:
        wx, wz = rot(a, lx, lz)
        px, pz = sx + wx, sz + wz
        mi = copy_model(src, name, zid, zone)
        pmn_, pmx_ = gltf_bounds(zd / zone['models'][mi]['file'])
        half = float(math.hypot(max(abs(pmn_[0]), abs(pmx_[0])), max(abs(pmn_[2]), abs(pmx_[2]))))
        for _ in range(20):                                # off the road (owner 2026-10-11: a cart in Midgard's road)
            qx, qz, qd = nearest_road(roads, px, pz)
            if qd >= half + 1.5:
                break
            ux, uz = (px - qx) / max(qd, 0.01), (pz - qz) / max(qd, 0.01)
            if qd < 0.01:
                ux, uz = out_x, out_z
            nx, nz = px + ux * 0.6, pz + uz * 0.6
            if fp.out_d(nx, nz) < half + 0.5:              # (never into the building)
                nx, nz = px + (ux - out_x) * 0.6, pz + (uz - out_z) * 0.6
            px, pz = nx, nz
        if name.lower().startswith('campfire'):
            py_ = g.footprint_min(px, pz, math.radians(yaw + py), pmn_, pmx_)
        else:
            # the ground under it levelled to its middle height and the prop set flush (on the lowest corner a slope
            # buried the haystack 1.2 m; on the middle the crates floated - owner 2026-10-11)
            py_ = g.footprint_median(px, pz, math.radians(yaw + py), pmn_, pmx_)
            g.flatten(px, pz, math.radians(yaw + py), pmn_, pmx_, py_, blend=2.5)
        place(zone, mi, name, px, py_, pz, yaw + py, collide=not name.lower().startswith('campfire'))
        lights_from(zone, src, name, px, py_, pz, math.radians(yaw + py))
        if name.lower() == 'campfire':
            src_zone = load_json(Z / f'zone{src:03d}/zone.json')
            eff = next((f['name'] for f in src_zone['fixtures'] if f.get('name', '').lower() == 'campfire effect'), None)
            if eff:
                ei = copy_model(src, eff, zid, zone)
                f = place(zone, ei, 'campfire effect', px, g.h(px, pz), pz, yaw + py, collide=False)
                f['source'] = 'world_object_effect'
                f['attach'] = 'wardnode'

    # the horn platform: a flat dry spot 30-50 m off, clear of the inn, its yard and the road
    avoid = [(sx, sz, b['radius'] + 12), (yard[0], yard[1], 14)]
    avoid += [(x, z, 16.0) for x, z in walk_route([(rx, rz)] + list(spec['road_walk']), 400)]   # the road itself
    avoid += [(x, z, 16.0) for x, z in walk_route(list(spec['road_other']), 900)]
    # every solid thing standing there (rocks, stones, ruins - trees are cleared): the platform keeps clear of it
    avoid += [(f['pos'][0], f['pos'][2], 11.0) for f in zone['fixtures']
              if not f.get('no_collision') and not TREE.search(f.get('name', '')) and f.get('source') != 'inn']
    avoid += [(door[0] + (rx - door[0]) * t / 8, door[1] + (rz - door[1]) * t / 8, 8.0) for t in range(9)]   # the inn's path
    avoid += [(gx_, gz_, 14.0) for gx_, gz_ in spec.get('road_guards', [])]   # the owner's guard spots (a guard stood
                                                                              # among Midgard's rune stones - 2026-10-11)
    # a spot the yard sees past the building (its path needs no detour), else the best flat spot (the path goes round)
    hs_ = flat_spot(g, wet, sx, sz, 30, 56, avoid, 7.0, roads, 14.0,
                    ok=lambda x, z: not fp.hits((yard[0] + (x - yard[0]) * 0.1, yard[1] + (z - yard[1]) * 0.1), (x, z), 1.0))         or flat_spot(g, wet, sx, sz, 30, 56, avoid, 7.0, roads, 14.0)
    hx, hz = hs_[1], hs_[2]
    hrx, hrz, hrd = nearest_road(roads, hx, hz)
    hyaw = math.degrees(math.atan2(-(hrx - hx) / hrd, -(hrz - hz) / hrd))
    # no tree on the platform or crowding it (the Horn Handler stood in Midgard's big trunk - owner 2026-10-11)
    zone['fixtures'] = [f for f in zone['fixtures']
                        if not (TREE.search(f.get('name', '')) and math.hypot(f['pos'][0] - hx, f['pos'][2] - hz) < 13.0)]
    pm = copy_model(PLATFORM[key], 'Portal Platform', zid, zone)
    pmin, pmax = gltf_bounds(zd / zone['models'][pm]['file'])
    prad = float(max(pmax[0] - pmin[0], pmax[2] - pmin[2]) / 2) * PLAT_SCALE
    ptop = float(pmax[1]) * PLAT_SCALE
    hy = float(np.median([g.h(hx + dx, hz + dz) for dx in np.linspace(-prad, prad, 7) for dz in np.linspace(-prad, prad, 7)
                          if dx * dx + dz * dz <= prad * prad])) - 0.05
    g.flatten(hx, hz, 0.0, np.array([-prad, 0.0, -prad]), np.array([prad, 0.0, prad]), hy, blend=3.0)
    place(zone, pm, 'Horn Platform', hx, hy, hz, hyaw, PLAT_SCALE)
    for name, src, ring, ang, sc in spec['horn']['dressing']:
        di = copy_model(src, name, zid, zone)
        if ring <= 0:                                      # a ring model: scaled to stand round the platform's edge
            rmin_, rmax_ = gltf_bounds(zd / zone['models'][di]['file'])
            rr = float(max(rmax_[0] - rmin_[0], rmax_[2] - rmin_[2]) / 2) or 1.0
            place(zone, di, name, hx, g.h(hx, hz), hz, hyaw, (prad + 1.6) / rr * sc)
        else:
            rr = prad + ring
            wx, wz = rot(math.radians(hyaw), rr * math.cos(math.radians(ang)), rr * math.sin(math.radians(ang)))
            # facing straight out from the platform (the model's front is +Z - owner 2026-10-11: two faced inward)
            place(zone, di, name, hx + wx, g.h(hx + wx, hz + wz), hz + wz, math.degrees(math.atan2(wx, wz)), sc)
    horn = horn_model(zid, zone)
    hmin, hmax = gltf_bounds(zd / zone['models'][horn]['file'])
    hlen = float(max(hmax - hmin))
    hscale = HORN_LEN / hlen if hlen > 0 else 4.0          # a great horn, on the platform
    # on open floor: the dressing can stand in the middle (Hibernia's grave ring has its tall stone there - owner
    # 2026-10-11: "the horn is stuck in its platform rock"); the horn lies along the ring where nothing stands
    hpx, hpz, hang = horn_spot(zone, zd, hx, hy + ptop, hz, prad, hyaw)
    place(zone, horn, 'Horn of Rallying', hpx, hy + ptop - float(hmin[1]) * hscale, hpz, hang, hscale)
    report['horn'] = {'pos': [hpx, hpz], 'platform_radius': prad, 'horn_scale': hscale}

    # paths: door -> road, yard -> horn platform; the yard trodden to dirt; no grass on floors and paths
    lbp = {}
    names = spec['path_layers']
    paint_disc(lbp, zone, zid, names, yard[0], yard[1], 7.0)
    for p0, p1 in zip(*(lambda r: (r, r[1:]))(fp.detour(door, (rx, rz)))):
        paint_line(lbp, zone, zid, names, p0, p1, 3.2)
    for p0, p1 in zip(*(lambda r: (r, r[1:]))(fp.detour(yard, (hx, hz), 3.0))):
        paint_line(lbp, zone, zid, names, p0, p1, 2.4)
    paint_disc(lbp, zone, zid, names, hx, hz, prad + 2.0)
    for k, (patch, ws) in lbp.items():
        for wi, w in enumerate(ws):
            Image.fromarray(np.clip(w, 0, 255).astype(np.uint8), 'RGBA').save(zd / patch['weights'][wi])
    dense = np.array(Image.open(zd / 'densemap.png'))
    clear_clutter(dense, g.size, sx, sz, b['radius'] + 2)
    clear_clutter(dense, g.size, hx, hz, prad + 2)
    for (x0, z0), (x1, z1) in [(door, (rx, rz)), (yard, (hx, hz))]:
        n = max(1, int(math.hypot(x1 - x0, z1 - z0) / 3))
        for i in range(n + 1):
            clear_clutter(dense, g.size, x0 + (x1 - x0) * i / n, z0 + (z1 - z0) * i / n, 2.0)
    Image.fromarray(dense).save(zd / 'densemap.png')

    # monster spawns inside the grounds move out to a ring just beyond (same monsters, levels, numbers)
    moved = []
    for s in npcs['spawns']:
        if int(s.get('realm', 0)) != 0:
            continue
        x, z = s['pos'][0], s['pos'][2]
        d_inn = math.hypot(x - sx, z - sz)
        d_horn = math.hypot(x - hx, z - hz)
        if d_inn >= CLEAR_INN and d_horn >= CLEAR_HORN:
            continue
        ang = math.atan2(z - sz, x - sx)
        for tries in range(48):
            r = RING[0] + (RING[1] - RING[0]) * ((d_inn / CLEAR_INN + tries * 0.37) % 1.0)
            aa = ang + (tries // 2) * 0.35 * (1 if tries % 2 else -1)
            nx, nz = sx + r * math.cos(aa), sz + r * math.sin(aa)
            gy = g.h(nx, nz)
            if math.hypot(nx - hx, nz - hz) > CLEAR_HORN + 4 and not wet(nx, nz, gy) and nearest_road(roads, nx, nz)[2] > 6:
                break
        moved.append({'name': s['name'], 'from': [round(x, 1), round(z, 1)], 'to': [round(nx, 1), round(nz, 1)]})
        s['pos'] = [nx, gy, nz]
        if 'path' in s:
            del s['path']

    # NPCs ------------------------------------------------------------
    eq = npcs.setdefault('equipment', {})
    added = []

    def look(src):
        sp, seq = spawn_of(*src)
        e = sp.get('equipment', '') or ''
        for one in str(e).split(';'):
            if one and one not in eq and one in seq:
                eq[one] = seq[one]
        return sp

    def inside(pt):
        lx, lz, fy = pt
        wx, wz = rot(a, lx, lz)
        return [sx + wx, by + fy, sz + wz]

    door_h = heading_to(out_x, out_z)
    in_h = heading_to(-out_x, -out_z)
    ik = spec['innkeeper']
    base, outfit = look(ik['look']), look(ik['outfit'])
    ifx, ifz = rot(a, *spec['innkeeper_face']) if 'innkeeper_face' in spec else (out_x, out_z)
    s = new_spawn(base, f'{key}-innkeeper', name=ik['name'], guild='Innkeeper', level=30, realm=spec['realm'],
                  role='innkeeper', class_type='GameInnkeeper', pos=inside(spec['inside']['innkeeper']),
                  heading=heading_to(ifx, ifz),
                  equipment=outfit.get('equipment', ''), respawn=0, flags=0)
    added.append(s)
    hl = spec['healer']
    base, outfit = look(hl['look']), look(hl['outfit'])
    added.append(new_spawn(base, f'{key}-healer', name=hl['name'], guild='Healer', level=35, realm=spec['realm'],
                           role='healer', class_type='GameHealer', revives_companions=True,
                           pos=inside(spec['inside']['healer']), heading=door_h,
                           equipment=outfit.get('equipment', ''), respawn=0, flags=0))
    # guards: two at the door, two by the road (copies of the town's own guards)
    gsrc = look(spec['guard'])
    side_x, side_z = -out_z, out_x
    rdx, rdz = (rx - door[0]), (rz - door[1])
    rl = math.hypot(rdx, rdz) or 1.0
    spots = [(door[0] + out_x * 3 + side_x * 3.5, door[1] + out_z * 3 + side_z * 3.5, door_h),
             (door[0] + out_x * 3 - side_x * 3.5, door[1] + out_z * 3 - side_z * 3.5, door_h),
             (rx - rdx / rl * 5 + side_x * 7, rz - rdz / rl * 5 + side_z * 7, heading_to(rdx, rdz)),
             (rx - rdx / rl * 5 - side_x * 7, rz - rdz / rl * 5 - side_z * 7, heading_to(rdx, rdz))]
    if spec.get('road_guards'):
        for k, (gx, gz) in enumerate(spec['road_guards']):     # watching the road, facing away from the inn
            spots[2 + k] = (gx, gz, heading_to(gx - sx, gz - sz))
    for i, (gx, gz, gh) in enumerate(spots):
        added.append(new_spawn(gsrc, f'{key}-guard-{i}', pos=[gx, g.h(gx, gz), gz], heading=gh))
    # the Horn Handler <Realm> by the horn (the horn does nothing yet)
    hsrc = look(spec['horn']['handler_look'])
    # the first spot round the platform's edge with nothing solid within 2 m and no guard within 4 m
    solid_ = [(f['pos'][0], f['pos'][2]) for f in zone['fixtures'] if not f.get('no_collision')
              and f.get('name') not in ('Horn Platform', 'Horn of Rallying') and math.hypot(f['pos'][0] - hx, f['pos'][2] - hz) < prad + 12]
    guards_ = [(gx_, gz_) for gx_, gz_ in spec.get('road_guards', [])] + [(sp_[0], sp_[1]) for sp_ in spots]
    hwx, hwz = rot(math.radians(hyaw), prad + 2.0, 0.0)
    for k_ in range(24):
        ang_ = math.radians(hyaw) + math.pi / 12 * ((k_ + 1) // 2) * (1 if k_ % 2 else -1)
        cx_, cz_ = (prad + 2.0) * math.sin(ang_), (prad + 2.0) * math.cos(ang_)
        if all(math.hypot(hx + cx_ - x_, hz + cz_ - z_) > 2.0 for x_, z_ in solid_)                 and all(math.hypot(hx + cx_ - x_, hz + cz_ - z_) > 4.0 for x_, z_ in guards_):
            hwx, hwz = cx_, cz_
            break
    added.append(new_spawn(hsrc, f'{key}-horn-handler', name='Horn Handler', guild=spec['horn']['guild'], level=50,
                           role='horn_handler', class_type='GameNPC', pos=[hx + hwx, g.h(hx + hwx, hz + hwz), hz + hwz],
                           heading=heading_to(-hwx, -hwz), respawn=0, flags=0))
    # the adventurers: out of the inn, up the road toward the town, idle, back (real NPCs, guard style, level 15)
    base = [(rx, rz)] + [p for p in spec['road_walk'] if math.hypot(p[0] - rx, p[1] - rz) > 15]
    route = on_road(roads, walk_route(base, ROAD_WALK_MAX))
    route = [p for i, p in enumerate(route) if i == 0 or math.dist(p, route[i - 1]) > 2.0]   # (snapped twins)
    report['route_wet'] = sum(1 for x, z in route if wet(x, z, g.h(x, z)))
    lounge = inside(spec['inside']['lounge'])
    yard_to_road = fp.detour(yard, (rx, rz))[1:-1]          # (a corner when the road lies behind the inn)
    LANES = [-1.8, -0.6, 0.6, 1.8]                         # metres off the road's middle: side by side, not in a file
    for i, nm in enumerate(spec['adventurers']):
        src = look(spec['adventurer_looks'][i % len(spec['adventurer_looks'])])
        ll = spec['inside']['lounge']
        my_lounge = inside((ll[0] + (i % 2) * 1.3 - 0.65, ll[1] + (i // 2) * 1.3 - 0.65, ll[2]))   # each its own seat
        lane = LANES[i % len(LANES)]
        mine = route[:max(4, len(route) - i * 6)]           # each idles at its own spot up the road
        walk = [my_lounge, [door[0] - out_x * 2, by + b['floor'], door[1] - out_z * 2],
                [door[0] + out_x * 2, g.h(door[0] + out_x * 2, door[1] + out_z * 2), door[1] + out_z * 2],
                [yard[0], g.h(*yard), yard[1]]] + [[x, g.h(x, z), z] for x, z in yard_to_road]
        for k, (x, z) in enumerate(mine):
            nx_, nz_ = mine[min(k + 1, len(mine) - 1)]
            px_, pz_ = mine[max(k - 1, 0)]
            dx_, dz_ = nx_ - px_, nz_ - pz_
            dl = math.hypot(dx_, dz_) or 1.0
            ox, oz = x - dz_ / dl * lane, z + dx_ / dl * lane
            walk.append([ox, g.h(ox, oz), oz])
        # every leg outside (from the outside door on) round the building; a point inside its outline is dropped
        # (owner 2026-10-11: an adventurer walked through Midgard's inn - its road runs right past the tavern)
        fixed = walk[:3]
        for q in walk[3:]:
            if fp.out_d(q[0], q[2]) < 1.0:
                continue
            p_ = fixed[-1]
            for c in fp.detour((p_[0], p_[2]), (q[0], q[2]), 1.0)[1:-1]:
                fixed.append([c[0], g.h(c[0], c[1]), c[1]])
            fixed.append(q)
        walk = fixed
        pts = []
        rng = __import__('random').Random(f'{key}-{i}')     # (the same inn every run)
        pace = rng.randint(58, 82)                          # units/s: each its own walking pace
        for j, p in enumerate(walk):
            wait = 0
            if j == 0:
                wait = rng.randint(300, 1500)                # tenths of a second: a drink inside (varied each time)
            elif j == len(walk) - 1:
                wait = rng.randint(200, 900)                 # idling up the road
            pts.append([p[0], p[1], p[2], pace, wait])
        added.append(new_spawn(src, f'{key}-adventurer-{i}', name=nm, guild='Adventurer', level=ADV_LEVEL,
                               realm=spec['realm'], role='guard', class_type='GameGuard', floors=True,
                               pos=my_lounge, heading=in_h, respawn=420, speed=191,
                               path={'type': 2, 'points': pts, 'jitter': True}, stats=src.get('stats', [30, 30, 30, 30])))
    for s in added:
        assert s['name'].lower() not in all_names or s.get('role') in ('guard',) or s['name'] == 'Horn Handler', s['name']
    npcs['spawns'].extend(added)
    g.save()
    save_json(zd / 'zone.json', zone)
    save_json(zd / 'npcs.json', npcs)

    # the game's data
    lab = map_label(zid, zone, sx, sz, 'ROADSIDE INN')
    report.update({
        'realm': key, 'town': spec['town'], 'door': [door[0], by + b['floor'], door[1]], 'yard': [yard[0], g.h(*yard), yard[1]],
        'road': [rx, rz], 'innkeeper': ik['name'], 'healer': hl['name'], 'horn_handler': 'Horn Handler',
        'courier': spec['courier'], 'map_label': lab, 'moved': moved, 'route_m': len(route) * 10,
        'arrive': [door[0] + out_x * 4, g.h(door[0] + out_x * 4, door[1] + out_z * 4), door[1] + out_z * 4],
    })
    return report


def map_label(zid, zone, x, z, text):
    """Where to write the label on the zone map: of eight spots around the inn, the one over the least painted detail
    (the map's own names and symbols stay readable). Returns {at: world x / z, offset: [dx, dy] in map fractions}."""
    m = load_json(ROOT / 'godot/content/maps/maps.json')['zones'][str(zid)]
    img = np.array(Image.open(ROOT / 'godot/content/maps/x4plus' / m['map']).convert('L')).astype(np.float32)
    n = img.shape[0]
    fx, fz = x / zone['size_m'], z / zone['size_m']
    w, h = 0.13, 0.03
    best = None
    for ox, oy in [(0.02, -0.035), (0.02, 0.012), (-0.15, -0.035), (-0.15, 0.012), (-0.065, -0.06), (-0.065, 0.035),
                   (0.03, -0.012), (-0.16, -0.012)]:
        x0, y0 = int((fx + ox) * n), int((fz + oy) * n)
        x1, y1 = int(x0 + w * n), int(y0 + h * n)
        if x0 < 0 or y0 < 0 or x1 >= n or y1 >= n:
            continue
        patch = img[y0:y1, x0:x1]
        gy, gx = np.gradient(patch)
        busy = float(np.mean(np.abs(gx)) + np.mean(np.abs(gy)))
        if best is None or busy < best[0]:
            best = (busy, ox, oy)
    return {'at': [x, z], 'offset': [best[1], best[2]], 'text': text}


def main():
    all_names = set()
    for f in Z.glob('zone*/npcs.json'):
        for s in load_json(f)['spawns']:
            if not s.get('inn'):
                all_names.add(s['name'].lower())
    data = {'inns': {}}
    for key, spec in INNS.items():
        r = build_inn(key, spec, all_names)
        data['inns'][key] = r
        print(key, 'zone', r['zone'], 'yaw %.0f' % r['yaw'], 'ground %.1f-%.1f' % tuple(r['ground']), 'road %.0f m' % r['road_m'],
              'trees', r['trees_cleared'], 'moved', len(r['moved']), 'route', r['route_m'], 'm wet', r['route_wet'], 'horn', [round(v) for v in r['horn']['pos']])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    save_json(OUT, data, 1)
    if '--export' in sys.argv:
        godot = ROOT / 'tools/godot_net/Godot_v4.7.2-stable_mono_win64.exe'
        ids = [str(s['zone']) for s in INNS.values()]
        subprocess.run([str(godot), '--headless', '--path', str(ROOT / 'godot'), '-s', 'res://tools/export_world_collision.gd', '--'] + ids, check=False)
        import os
        nav = Path(os.environ.get('APPDATA', '')) / 'Godot/app_userdata/MMOEngine/world/nav'
        dropped = 0
        for zid_ in ids:
            for f in nav.glob(f'zone{int(zid_):03d}_*.res'):
                f.unlink()
                dropped += 1
        print('dropped', dropped, 'cached navigation tiles (rebuilt when the host next loads those zones)')
    print('wrote', OUT)


if __name__ == '__main__':
    main()
