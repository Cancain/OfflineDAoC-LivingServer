"""Guild emblems as the client builds them (owner 2026-10-17: a high-quality guild UI for the server's gamebot guilds).
Writes godot/content/emblems/emblems.json and insignia/<file>.png.

The emblem number (EmblemDialogReponseHandler; equipment / inventory packets): logo << 9 | pattern << 7 | primary << 3
| secondary, the logo's 0x10000 bit for insignia 128-255.
- gamedata patterns.csv: set 1 = the 16 primary colours, set 2 = the 8 secondary colours.
- game.dll 0x481606 (called from 0x49203a for every primary * 8 + secondary): four 2 x 4 pixel textures per colour pair,
  each pixel the primary (mask 0) or the secondary (mask 1); with no emblem a flat 0x80 grey (index 0x200).
- gamedata insignia.csv: logo id -> insignia/<file>.dds (black logos on white).
- Drawn (game.dll 0x481901 for items, the $insigniaTexture pixel shaders for figures): pattern (UV set 0) x item texture
  x 2 x logo's red (the logo's UV set; black = dark).

    python pipeline/build_emblems.py
"""
import csv, io, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk
from PIL import Image

OUT = ROOT / 'godot/content/emblems'
# game.dll 0x4816de: the masks of the four patterns, row by row (2 wide, 4 tall), 1 = the secondary colour
MASKS = [[0, 1, 1, 0, 1, 0, 1, 0], [0, 1, 0, 1, 0, 1, 1, 0], [1, 1, 1, 1, 0, 0, 1, 0], [0, 0, 0, 0, 0, 0, 0, 0]]


def main():
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    rows = lambda name: list(csv.reader(io.StringIO(g[name].decode('latin1'))))
    primary, secondary = [None] * 16, [None] * 8
    for r in rows('patterns.csv'):
        if len(r) >= 6 and r[0].strip().isdigit() and r[1].strip().isdigit():
            rgb = [int(r[3]), int(r[4]), int(r[5])]
            (primary if r[0].strip() == '1' else secondary)[int(r[1])] = {'name': r[2].split('_', 1)[-1], 'rgb': rgb}
    (OUT / 'insignia').mkdir(parents=True, exist_ok=True)
    logos = {}
    for r in rows('insignia.csv'):
        if len(r) >= 3 and r[0].strip().isdigit() and r[2].strip():
            src = CLIENT / 'insignia' / r[2].strip()
            if not src.exists():
                src = next((p for p in (CLIENT / 'insignia').iterdir() if p.name.lower() == r[2].strip().lower()), None)
            if src is None:
                print('missing', r[2])
                continue
            name = src.stem.lower()
            dst = OUT / 'insignia' / f'{name}.png'
            if not dst.exists():
                Image.open(src).convert('RGB').save(dst)
            logos[int(r[0])] = {'file': name, 'name': r[1].strip()}
    data = {'primary': primary, 'secondary': secondary, 'masks': MASKS, 'logos': logos}
    (OUT / 'emblems.json').write_text(json.dumps(data, indent=1), encoding='utf-8')
    print(len(logos), 'logos;', sum(1 for c in primary if c), 'primary,', sum(1 for c in secondary if c), 'secondary colours')


if __name__ == '__main__':
    main()
