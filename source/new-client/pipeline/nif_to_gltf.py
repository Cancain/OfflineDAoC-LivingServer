"""DAoC NIF (Gamebryo 10.1) -> glTF 2.0 static mesh in bind pose (MMOEngine, step 2).

    python nif_to_gltf.py <model.nif> <out.gltf> --part Body1=textures/body.png --part HeadA1=textures/head.png ...

Each --part names a NiNode in the NIF (e.g. HeadA1, Body1, Arms1) and the texture image its mesh should use
("HeadA1@1=..." picks UV set 1 instead of 0; DAoC heads carry the face mapping in set 1). The
image path is written into the glTF as a relative URI, so the same mesh can be pointed at different texture sets.
Only the chosen parts are exported (a DAoC figure holds every body-part variant plus LODs; the client picks parts
and skins at runtime). Geometry is placed by walking the NiNode transforms to the root, converted from NIF Z-up to
glTF Y-up and scaled from DAoC units to metres. An optional pose (bone rotations, e.g. arms lowered out of the
T-pose) is baked in with the NIF's own skin weights. Real skinning and animation come later; this is for previews.
"""
import argparse, base64, json, struct, sys, time
time.clock = time.perf_counter                       # pyffi 2.2.3 still calls time.clock (removed in Python 3.8)
import numpy as np
from pyffi.formats.nif import NifFormat

UNITS_TO_METRES = 0.025                              # a DAoC humanoid is ~72 units tall -> ~1.8 m


def load(path):
    data = NifFormat.Data()
    with open(path, 'rb') as f:
        data.read(f)
    return data


def local_matrix(block):
    # pyffi uses row vectors (p' = p @ M), translation in the last row
    return np.array(block.get_transform().as_list(), dtype=np.float64)


def axis_rotation(axis, degrees):
    a = np.radians(degrees)
    c, s = np.cos(a), np.sin(a)
    i, j = {'x': (1, 2), 'y': (2, 0), 'z': (0, 1)}[axis]
    r = np.identity(4)
    r[i, i], r[i, j], r[j, i], r[j, j] = c, s, -s, c
    return r


def world_matrices(roots, pose=None):
    """Map every NiAVObject to its world matrix by walking down from the roots.
    pose = {bone name: (axis, degrees)} rotates that bone in its own frame before its children are placed."""
    out = {}
    pose = pose or {}

    def walk(block, parent):
        local = local_matrix(block)
        name = block.name.decode()
        if name in pose:
            local = axis_rotation(*pose[name]) @ local
        m = local @ parent
        out[id(block)] = (block, m)
        if isinstance(block, NifFormat.NiNode):
            for child in block.children:
                if child is not None:
                    walk(child, m)

    for r in roots:
        if isinstance(r, NifFormat.NiAVObject):
            walk(r, np.identity(4))
    return out


def shapes_under(node):
    found = []
    for child in getattr(node, 'children', []):
        if isinstance(child, NifFormat.NiTriShape):
            found.append(child)
        elif isinstance(child, NifFormat.NiNode):
            found.extend(shapes_under(child))
    return found


Z_UP_TO_Y_UP = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], dtype=np.float64)   # (x, y, z) -> (x, z, -y)


def skinned(shape, bind, posed):
    """Per-vertex matrix taking bind-pose world positions to posed world positions (linear blend skinning)."""
    n = shape.data.num_vertices
    acc = np.zeros((n, 4, 4))
    total = np.zeros(n)
    si = shape.skin_instance
    if si is not None and si.data.has_vertex_weights:
        for bone, bl in zip(si.bones, si.data.bone_list):
            delta = np.linalg.inv(bind[id(bone)][1]) @ posed[id(bone)][1]
            for vw in bl.vertex_weights:
                acc[vw.index] += vw.weight * delta
                total[vw.index] += vw.weight
    unweighted = total < 1e-6
    acc[unweighted] = np.identity(4)
    acc[~unweighted] /= total[~unweighted, None, None]
    return acc


def shape_arrays(shape, bind, posed, uv_set=0):
    d = shape.data
    world = bind[id(shape)][1]
    deform = skinned(shape, bind, posed)
    pos = np.array([[v.x, v.y, v.z] for v in d.vertices], dtype=np.float64)
    pos = np.c_[pos, np.ones(len(pos))] @ world
    pos = np.einsum('ni,nij->nj', pos, deform)[:, :3] @ Z_UP_TO_Y_UP.T * UNITS_TO_METRES
    if d.has_normals:
        nrm = np.array([[n.x, n.y, n.z] for n in d.normals], dtype=np.float64) @ world[:3, :3]
        nrm = np.einsum('ni,nij->nj', nrm, deform[:, :3, :3]) @ Z_UP_TO_Y_UP.T
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    else:
        nrm = None
    uv = np.array([[t.u, t.v] for t in d.uv_sets[uv_set]], dtype=np.float32) if d.num_uv_sets > uv_set else None
    tris = np.array([[t.v_1, t.v_2, t.v_3] for t in d.triangles], dtype=np.uint32)
    return pos.astype(np.float32), None if nrm is None else nrm.astype(np.float32), uv, tris


class GltfWriter:
    def __init__(self):
        self.buf = bytearray()
        self.doc = {'asset': {'version': '2.0', 'generator': 'MMOEngine nif_to_gltf'},
                    'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [], 'materials': [],
                    'textures': [], 'images': [], 'samplers': [{'magFilter': 9729, 'minFilter': 9987}],
                    'accessors': [], 'bufferViews': [], 'buffers': []}

    def accessor(self, arr, comp, kind, target):
        while len(self.buf) % 4:
            self.buf.append(0)
        raw = arr.tobytes()
        self.doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(self.buf), 'byteLength': len(raw), 'target': target})
        self.buf += raw
        acc = {'bufferView': len(self.doc['bufferViews']) - 1, 'componentType': comp, 'count': len(arr), 'type': kind}
        if kind == 'VEC3' and comp == 5126:
            acc['min'], acc['max'] = arr.min(0).tolist(), arr.max(0).tolist()
        self.doc['accessors'].append(acc)
        return len(self.doc['accessors']) - 1

    def material(self, name, image_uri):
        self.doc['images'].append({'uri': image_uri})
        self.doc['textures'].append({'sampler': 0, 'source': len(self.doc['images']) - 1})
        self.doc['materials'].append({'name': name, 'doubleSided': True,  # skin alpha is a hair/dye tint mask, not transparency
                                      'pbrMetallicRoughness': {'baseColorTexture': {'index': len(self.doc['textures']) - 1},
                                                               'metallicFactor': 0.0, 'roughnessFactor': 0.9}})
        return len(self.doc['materials']) - 1

    def mesh(self, name, pos, nrm, uv, tris, material):
        attrs = {'POSITION': self.accessor(pos, 5126, 'VEC3', 34962)}
        if nrm is not None:
            attrs['NORMAL'] = self.accessor(nrm, 5126, 'VEC3', 34962)
        if uv is not None:
            attrs['TEXCOORD_0'] = self.accessor(uv, 5126, 'VEC2', 34962)
        idx = self.accessor(tris.reshape(-1), 5125, 'SCALAR', 34963)
        self.doc['meshes'].append({'name': name, 'primitives': [{'attributes': attrs, 'indices': idx, 'material': material}]})
        self.doc['nodes'].append({'name': name, 'mesh': len(self.doc['meshes']) - 1})
        self.doc['scenes'][0]['nodes'].append(len(self.doc['nodes']) - 1)

    def save(self, path):
        self.doc['buffers'] = [{'byteLength': len(self.buf),
                                'uri': 'data:application/octet-stream;base64,' + base64.b64encode(bytes(self.buf)).decode()}]
        with open(path, 'w') as f:
            json.dump(self.doc, f)


def convert(nif_path, out_path, parts, pose=None):
    data = load(nif_path)
    worlds = world_matrices(data.roots)
    posed = world_matrices(data.roots, pose)
    nodes = {block.name.decode(): block for block, _ in worlds.values() if isinstance(block, NifFormat.NiNode)}
    w = GltfWriter()
    for spec, image in parts.items():
        part, _, uv_set = spec.partition('@')
        if part not in nodes:
            sys.exit(f'part {part!r} not in {nif_path}; nodes: {sorted(nodes)}')
        mat = w.material(part, image)
        for shape in shapes_under(nodes[part]):
            pos, nrm, uv, tris = shape_arrays(shape, worlds, posed, int(uv_set or 0))
            w.mesh(shape.name.decode(), pos, nrm, uv, tris, mat)
            print(f'{part}: {shape.name.decode()} {len(pos)} verts {len(tris)} tris -> {image}')
    w.save(out_path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('nif')
    ap.add_argument('out')
    ap.add_argument('--part', action='append', required=True, help='NodeName=relative/texture.png')
    ap.add_argument('--pose', action='append', default=[], help='"Bip01 L UpperArm=z:-70" (bone=axis:degrees)')
    args = ap.parse_args()
    pose = {}
    for p in args.pose:
        bone, rot = p.split('=', 1)
        axis, deg = rot.split(':')
        pose[bone] = (axis, float(deg))
    convert(args.nif, args.out, dict(p.split('=', 1) for p in args.part), pose)


if __name__ == '__main__':
    main()
