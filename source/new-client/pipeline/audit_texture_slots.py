"""Count every NiTexturingProperty slot (and the UV set it uses) across the client's NIFs, so the converter and the
engine material can be checked to cover all of them (MMOEngine pipeline audit)."""
import collections, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from corpus_test_nif import nifs
from netimmerse import read_nif
from assets_pipeline import CLIENT

SLOTS = ('base_texture', 'dark_texture', 'detail_texture', 'gloss_texture', 'glow_texture', 'bump_map_texture',
         'decal_0_texture', 'decal_1_texture', 'decal_2_texture', 'decal_3_texture')

def main():
    slots, uvsets, apply_modes, other_props, files = collections.Counter(), collections.Counter(), collections.Counter(), collections.Counter(), 0
    examples = {}
    for path, raw in nifs():
        try:
            nif = read_nif(raw)
        except Exception:
            continue
        files += 1
        rel = path.replace('\\', '/').split('/app/', 1)[-1]
        folder = rel.split('/', 1)[0]
        for b in nif.blocks:
            if b.type == 'NiTexturingProperty':
                apply_modes[b.get('apply_mode')] += 1
                for s in SLOTS:
                    if b.get('has_' + s):
                        uv = int(b[s].get('uv_set') or 0)
                        slots[(s, folder)] += 1
                        uvsets[(s, uv)] += 1
                        examples.setdefault((s, uv), path)
                if b.get('num_shader_textures'):
                    other_props[('shader_textures', folder)] += 1
            elif b.type in ('NiMultiTextureProperty', 'NiTextureProperty', 'NiTextureModeProperty', 'NiTextureEffect', 'NiSpecularProperty', 'NiWireframeProperty'):
                other_props[(b.type, folder)] += 1
    print('files', files)
    print('slots by folder:'); [print('  ', k, v) for k, v in sorted(slots.items())]
    print('slot uv sets:'); [print('  ', k, v, examples[k][-70:]) for k, v in sorted(uvsets.items())]
    print('apply modes', dict(apply_modes))
    print('other texture-related blocks:'); [print('  ', k, v) for k, v in sorted(other_props.items())]

if __name__ == '__main__':
    main()
