"""Login / loading screen art for MMOEngine (client assets + the owner's chosen pieces), upscaled with x4plus.

    python build_ui.py            # -> godot/content/ui/{original,x4plus}/*.png + fonts/

Sources (owner 2026-10-09):
  login background   app/data/login.mpk smcamback.bmp  (the client's stone chamber, 640x480)
  login flames       app/data/login.mpk flames.bmp     (16 frames of 60x210 over a knotwork band; black = empty)
  loading screen     assets/ui_source/daoc_box_art.jpg (the original Dark Age of Camelot box art, owner-provided)
  logo               assets/ui_source/realm_emblem.png (the three-realm emblem from the OfflineDAoC 0.35 launcher)
  loading bar        app/data/splashloadbar1.tga (empty) / splashloadbar2.tga (full), the client's bronze bar
  fonts              app/ui/fonts/minionpro-*.ttf, myriadpro-*.ttf (shipped with the client)
  tips               app/data/loading/tips.dat (post-1.65 tips filtered out, see POST_165)
  music              app/sounds/title.mp3 (cc_mp3s 1 mp3_Title, hard-coded login/character-select music)
Upscale: Real-ESRGAN x4plus at full 4x (screen art is viewed full-screen).
"""
import io, json, re, shutil, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from build_zone import upscale_dir
import build_sounds

OUT = ROOT / 'godot/content/ui'
# app/data/loading/tips.dat is the client's last (2019) tip list. This is a 1.65 game: tips about later content are
# left out (kept in the json's 'dropped' list for the owner to review). Matching is case-insensitive.
POST_165 = ['catacombs', 'labyrinth', 'gaheris', 'mordred', 'champion', 'master level', 'arbiter', 'rog ',
            'trinket', 'ellan vannin', 'infernal engineering', 'siege tower', 'outpost', 'siege tent', 'battle ram',
            'war ram', 'configurations', 'siegemaster', 'hookpoint', 'keep types', 'new keeps', 'level six',
            'keep guard', 'wooden grate', 'maintenance costs', 'siege supply', 'battleground has restrictions',
            'bainshee', 'zarees', 'darkageofcamelot.com', 'character models to classic', 'guild merit',
            'realm rank 12', 'higher level gear', 'repair keeps, towers', 'salvage', 'blocking rate is capped']


def main():
    orig = OUT / 'original'
    orig.mkdir(parents=True, exist_ok=True)
    (ROOT / 'godot/content/.gdignore').touch()
    login = read_mpk(str(CLIENT / 'data/login.mpk'))
    Image.open(io.BytesIO(login['smcamback.bmp'])).convert('RGB').save(orig / 'login_background.png')
    Image.open(io.BytesIO(login['flames.bmp'])).convert('RGB').save(orig / 'login_flames.png')
    Image.open(ROOT / 'assets/ui_source/daoc_box_art.jpg').convert('RGB').save(orig / 'loading_box_art.png')
    Image.open(ROOT / 'assets/ui_source/realm_emblem.png').convert('RGBA').save(orig / 'realm_emblem.png')
    import numpy as np
    for n in ('splashloadbar1', 'splashloadbar2'):
        # the bar art sits on solid black: key the black out so only the bronze bar shows (owner: no black border)
        rgb = np.asarray(Image.open(CLIENT / f'data/{n}.tga').convert('RGB')).astype(np.int32)
        alpha = np.clip((rgb.max(axis=2) - 10) * 12, 0, 255).astype(np.uint8)
        Image.fromarray(np.dstack([rgb.astype(np.uint8), alpha]), 'RGBA').save(orig / f'{n}.png')
    fonts = OUT / 'fonts'
    fonts.mkdir(exist_ok=True)
    for f in (CLIENT / 'ui/fonts').glob('*.ttf'):
        shutil.copy2(f, fonts / f.name.lower())
    upscale_dir(orig, OUT / 'x4plus', factor_after=4)
    # the title music the client hard-codes for its login / character select (cc_mp3s.csv 1 mp3_Title, title.mp3)
    print('title music:', build_sounds.export(set(), {1}) or 'ok')
    tips, dropped = [], []
    for line in (CLIENT / 'data/loading/tips.dat').read_text(encoding='latin1').splitlines():
        t = re.sub(r'\s+', ' ', line).strip()
        if not t:
            continue
        (dropped if any(k in t.lower() for k in POST_165) else tips).append(t)
    (OUT / 'loading_tips.json').write_text(json.dumps({'source': 'app/data/loading/tips.dat', 'tips': tips,
                                                       'dropped': dropped}, indent=1), encoding='utf-8')
    print(f'loading tips: {len(tips)} kept, {len(dropped)} left out as post-1.65')
    for p in sorted((OUT / 'x4plus').glob('*.png')):
        print(p.name, Image.open(p).size)


if __name__ == '__main__':
    main()
