"""Add walk links (Detour off-mesh connections) to an installed Detour MSET .nav.

A link joins two floors the mesh builder left apart although a player walks between them: a step a
little higher than the builder's walkable climb (28.8 units). Hall of the Corrupt (zone 277,
2026-10-22): the ramp up from Lord Gildas's room meets the main floor at a single 32-unit step, so
the raid's route stopped above his room and the raid ended "Route blocked".

python add_offmesh.py <in.nav> <out.nav> ax,ay,az:bx,by,bz [ax,ay,az:bx,by,bz ...]

World coordinates (x, y, z up), each end standing on its floor. Both ends must lie in the same
tile. The link is two-way, flagged Walk, area 0, radius 16, and is appended after the tile's
polygons and vertices the way dtCreateNavMeshData lays them out (off-mesh polygons last, not in
the BV tree, no detail mesh), with link capacity for it. The rest of the file is kept byte for byte.
Check the result with navcomp (same area) and a real-Detour probe (UT_RaidDungeonRoutesProbe).
"""
import struct, sys
from navdiff import tiles

HEADER = "<5iI9i3f3f3ff"
DT_POLYTYPE_OFFMESH = 1
DT_OFFMESH_CON_BIDIR = 1
WALK = 0x01
RADIUS = 16.0  # world units


def _tile_of(ts, x, y):
    rx, rz = x / 32, y / 32
    for key, (_, data) in ts.items():
        h = struct.unpack_from(HEADER, data, 0)
        bmin, bmax = h[18:21], h[21:24]
        if bmin[0] <= rx < bmax[0] and bmin[2] <= rz < bmax[2]:
            return key
    return None


def add_links(data, links):
    h = list(struct.unpack_from(HEADER, data, 0))
    poly_count, vert_count, max_links = h[6], h[7], h[8]
    dm, dv, dt, bv, om_count, om_base = h[9], h[10], h[11], h[12], h[13], h[14]
    off = 100
    verts = data[off: off + vert_count * 12]; off += vert_count * 12
    polys = data[off: off + poly_count * 32]; off += poly_count * 32
    off += max_links * 16  # links are rebuilt by Detour when the tile is added
    rest_len = dm * 12 + dv * 12 + dt * 4 + bv * 16
    rest = data[off: off + rest_len]; off += rest_len
    cons = data[off: off + om_count * 36]; off += om_count * 36
    assert off == len(data), f"unexpected tile layout ({off} != {len(data)})"
    if om_count == 0:
        om_base = poly_count
    new_verts, new_polys, new_cons = bytearray(verts), bytearray(polys), bytearray(cons)
    for a, b in links:
        va = vert_count
        for p in (a, b):
            new_verts += struct.pack("<3f", p[0] / 32, p[2] / 32, p[1] / 32)
        vert_count += 2
        vs = [va, va + 1, 0, 0, 0, 0]
        new_polys += struct.pack("<I6H6HHBB", 0xFFFFFFFF, *vs, *([0] * 6), WALK, 2, (DT_POLYTYPE_OFFMESH << 6) | 0)
        new_cons += struct.pack("<6ffHBBI", a[0] / 32, a[2] / 32, a[1] / 32, b[0] / 32, b[2] / 32, b[1] / 32,
                                RADIUS / 32, poly_count, DT_OFFMESH_CON_BIDIR, 0xFF, 0)
        poly_count += 1
        om_count += 1
    # Room for each link's two ends to link to the floor and back (Detour sizes it edges + portals*2 + links*2).
    max_links += 4 * len(links)
    h[6], h[7], h[8], h[13], h[14] = poly_count, vert_count, max_links, om_count, om_base
    return (struct.pack(HEADER, *h) + bytes(new_verts) + bytes(new_polys) + bytes(max_links * 16) + rest
            + bytes(new_cons))


def main(src, dst, specs):
    raw = open(src, "rb").read()
    head, ts, order = tiles(src)
    per_tile = {}
    for spec in specs:
        a, b = (tuple(map(float, part.split(","))) for part in spec.split(":"))
        ka, kb = _tile_of(ts, a[0], a[1]), _tile_of(ts, b[0], b[1])
        if ka is None or ka != kb:
            sys.exit(f"{spec}: both ends must be in one tile (got {ka} and {kb})")
        per_tile.setdefault(ka, []).append((a, b))
    body = bytearray(head)
    off = 40
    for k in order:
        ref, data = ts[k]
        pad = raw[off + 12: off + 16]
        off += 16 + len(data)
        if k in per_tile:
            data = add_links(data, per_tile[k])
            print(f"tile {k}: {len(per_tile[k])} link(s)")
        body += struct.pack("<Qi", ref, len(data)) + pad + data
    body += raw[off:]
    open(dst, "wb").write(body)


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
