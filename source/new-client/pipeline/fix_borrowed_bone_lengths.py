"""Borrowed bone lengths out of the built monster clips (owner 2026-10-15: the Bonedancer commander's "weird empty
space" at the elbows / knees). A figure playing another skeleton's anim set got that skeleton's fixed bone
translations - the forearm pushed 2.7 units out, a gap at the joint. nif_character.borrowed_length now leaves them out
of new builds; this drops them from the glTFs already built (content/monsters/*/model.gltf), the channel and its
sampler. Repack afterwards: godot/tools/pack_scenes.gd -- res://content/monsters.

    python pipeline/fix_borrowed_bone_lengths.py [--backup=<dir>] [--dry]
"""
import base64, json, shutil, sys
from pathlib import Path
import numpy as np
from assets_pipeline import ROOT
from nif_character import borrowed_length

MON = ROOT / 'godot/content/monsters'
TYPES = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def reader(g, base):
    cache = {}

    def buf(i):
        if i not in cache:
            uri = g['buffers'][i]['uri']
            cache[i] = base64.b64decode(uri.split(',', 1)[1]) if uri.startswith('data:') else (base / uri).read_bytes()
        return cache[i]

    def acc(i):
        a = g['accessors'][i]
        bv = g['bufferViews'][a['bufferView']]
        n = WIDTH[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        return np.frombuffer(buf(bv['buffer']), dtype=TYPES[a['componentType']], count=a['count'] * n, offset=off).reshape(a['count'], n)
    return acc


def main():
    backup = next((Path(a.split('=', 1)[1]) for a in sys.argv if a.startswith('--backup=')), None)
    dry = '--dry' in sys.argv
    files = changed = dropped = 0
    for p in sorted(MON.glob('*/model.gltf')):
        files += 1
        g = json.loads(p.read_text(encoding='utf-8'))
        acc = reader(g, p.parent)
        nodes = g.get('nodes', [])
        n_drop = 0
        for an in g.get('animations', []):
            keep_ch, keep_s, remap = [], [], {}
            for c in an['channels']:
                t = c['target']
                if t.get('path') == 'translation':
                    node = nodes[t['node']]
                    vals = acc(an['samplers'][c['sampler']]['output'])
                    if borrowed_length(node.get('name', ''), vals, node.get('translation', [0, 0, 0])):
                        n_drop += 1
                        continue
                s = c['sampler']
                if s not in remap:
                    remap[s] = len(keep_s)
                    keep_s.append(an['samplers'][s])
                keep_ch.append(dict(c, sampler=remap[s]))
            an['channels'], an['samplers'] = keep_ch, keep_s
        if n_drop:
            changed += 1
            dropped += n_drop
            print(p.parent.name, n_drop)
            if not dry:
                if backup:
                    (backup / p.parent.name).mkdir(parents=True, exist_ok=True)
                    shutil.copy2(p, backup / p.parent.name / p.name)
                p.write_text(json.dumps(g, separators=(',', ':')), encoding='utf-8')
    print(files, 'models,', changed, 'changed,', dropped, 'channels dropped', '(dry run)' if dry else '')


if __name__ == '__main__':
    main()
