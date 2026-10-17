"""Give converted models' split-lit materials their diffuse colour (owner 2026-10-15: Trollheim's ice wall super
blue - nif_static.material_spec stored only diffuse / ambient, capped at 4, which loses the diffuse wherever the
ambient colour has no such channel). Each model whose diffuse_tint hit the cap is converted again into a scratch
file and the new 'diffuse' copied onto the matching material (same base texture, tint and diffuse_tint); nothing else
in the model changes. Then repack: Godot --headless --path godot -s res://tools/pack_scenes.gd -- res://content

    python pipeline/fill_split_diffuse.py [--all]      (--all: every split-lit model, not only the capped ones)
"""
import json, os, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import MpakArchive
import nif_static

CONTENT = ROOT / 'godot/content'


def nif_index():
    """{nif basename lower: (loose path | (archive, entry))} for the client's effects and zone NIFs."""
    out = {}
    for root, _, files in os.walk(CLIENT):
        for f in files:
            low = f.lower()
            if low.endswith('.nif'):
                out.setdefault(low[:-4], Path(root) / f)
            elif low.endswith('.npk') and 'zones' in root.lower():
                try:
                    names = MpakArchive(os.path.join(root, f)).names()
                except Exception:
                    continue
                for n in names:
                    if n.lower().endswith('.nif'):
                        out.setdefault(n.lower()[:-4], (os.path.join(root, f), n))
    return out


def raw_of(src):
    if isinstance(src, tuple):
        return MpakArchive(src[0]).read(src[1])
    return Path(src).read_bytes()


def key(m):
    return (str(m.get('slots', {}).get('base', {}).get('tex', '')).replace('__x2', ''), tuple(m.get('tint', [])),
            tuple(m.get('diffuse_tint', [])))


def main():
    every = '--all' in sys.argv
    idx = nif_index()
    done = 0
    for f in sorted(CONTENT.rglob('*.gltf')):
        text = f.read_text(encoding='utf-8')
        if 'diffuse_tint' not in text:
            continue
        g = json.loads(text)
        mats = g.get('extras', {}).get('nif_materials', [])
        todo = [m for m in mats if m.get('diffuse_tint') and 'diffuse' not in m and
                (every or any(d >= 3.99 for d in m['diffuse_tint']))]
        if not todo:
            continue
        stem = f.parent.name if f.name == 'model.gltf' else f.stem
        src = idx.get(stem.lower())
        if src is None:
            print('no NIF for', f.relative_to(CONTENT))
            continue
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'm.gltf'
            nif_static.convert(raw_of(src), str(out))
            fresh = json.loads(out.read_text(encoding='utf-8')).get('extras', {}).get('nif_materials', [])
        by_key = {key(m): m['diffuse'] for m in fresh if 'diffuse' in m}
        n = 0
        for m in todo:
            d = by_key.get(key(m))
            if d is not None:
                m['diffuse'] = d
                n += 1
        if n:
            f.write_text(json.dumps(g), encoding='utf-8')
            done += 1
        print(f.relative_to(CONTENT), f'{n}/{len(todo)}')
    print(done, 'models given their diffuse colours')


if __name__ == '__main__':
    main()
