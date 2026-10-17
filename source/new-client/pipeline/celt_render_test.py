"""Celt NPC render test: original skins vs Real-ESRGAN upscaled skins on the same model, rendered in Godot.

    python celt_render_test.py

Writes godot/tests/celt/:
  textures/original/*.png      the client's skins as they are (128-256 px)
  textures/x4plus/*.png        Real-ESRGAN realesrgan-x4plus (4x, detailed)
  textures/anime/*.png         Real-ESRGAN realesrgan-x4plus-anime (4x, cleaner painted look)
  celt_<set>.gltf              HCeltM.NIF basic-clothes parts pointing at that texture set
The Godot scene tests/celt/render.tscn loads one glTF per run and saves a screenshot (see render.gd).
"""
import io, os, subprocess, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from daoc_mpk import read_mpk
from assets_pipeline import CLIENT
import nif_to_gltf

OUT = ROOT / 'godot/tests/celt'
ESRGAN = ROOT / 'tools/realesrgan/realesrgan-ncnn-vulkan.exe'
# NIF part -> (skin archive, texture) for a Celt male in basic clothes
PARTS = {
    'HeadA1@1': ('skin007.mpk', 'c_mhed1.dds'),
    'Body1': ('skin006.mpk', 'c_cth0_body1m.dds'),
    'LBody1': ('skin006.mpk', 'c_cth0_lbody1.dds'),
    'Arms1': ('skin006.mpk', 'c_cth0_arm1.dds'),
    'Legs1': ('skin006.mpk', 'c_cth0_leg1.dds'),
    'Gloves1': ('skin006.mpk', 'c_cth0_glov1.dds'),
    'Boots1': ('skin006.mpk', 'c_cth0_boot1.dds'),
}
# arms lowered out of the bind T-pose into a relaxed standing pose
POSE = {'Bip01 L UpperArm': ('y', 75), 'Bip01 R UpperArm': ('y', -75)}
SETS = {'x4plus': 'realesrgan-x4plus', 'anime': 'realesrgan-x4plus-anime'}


def main():
    orig = OUT / 'textures/original'
    orig.mkdir(parents=True, exist_ok=True)
    archives = {}
    for part, (archive, tex) in PARTS.items():
        if archive not in archives:
            archives[archive] = read_mpk(str(CLIENT / 'figures/skins' / archive))
        Image.open(io.BytesIO(archives[archive][tex])).convert('RGBA').save(orig / (tex[:-4] + '.png'))
    for name, model in SETS.items():
        dst = OUT / 'textures' / name
        dst.mkdir(parents=True, exist_ok=True)
        # whole folder in one call; the exe runs on the GPU through Vulkan
        subprocess.run([str(ESRGAN), '-i', str(orig), '-o', str(dst), '-n', model, '-s', '4', '-f', 'png'],
                       cwd=ESRGAN.parent, check=True)
    for name in ['original', *SETS]:
        parts = {part: f'textures/{name}/{tex[:-4]}.png' for part, (_, tex) in PARTS.items()}
        nif_to_gltf.convert(str(CLIENT / 'figures/HCeltM.NIF'), str(OUT / f'celt_{name}.gltf'), parts, POSE)
    for p in sorted((OUT / 'textures').rglob('*.png')):
        print(p.relative_to(OUT), Image.open(p).size)


if __name__ == '__main__':
    main()
