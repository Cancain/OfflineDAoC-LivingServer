"""The style number in the server's combat packets -> the style's animation (0.36c).

CombatAnimation carries the style's Icon (or, with a two-handed weapon, its TwoHandAnimation) - a gamedata styles.csv
row; that row's Animation column is the canims.csv animation (content/characters/style_clips.json names its clip),
the lookup the client made. Writes godot/content/rules/style_anims.json {styles.csv id: animation}, and
godot/content/rules/style_fx.json {styles.csv id: [Imagenum, Duration ms, Buildup ms, Red, Green, Blue, Hit Effect]}:
the style's coloured afterimage trail behind the weapon (Imagenum copies of it, Buildup ms into the swing, for
Duration ms, in Red / Green / Blue) and its hit effect on the target (a speffects id, 0 none).

    python pipeline/build_style_anims.py
"""
import csv
import io
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk

g = read_mpk(str(CLIENT / 'gamedata.mpk'))
out = {r[0].strip(): int(r[3]) for r in csv.reader(io.StringIO(g['styles.csv'].decode('latin1')))
       if len(r) > 3 and r[0].strip().isdigit() and r[3].strip().isdigit()}
(ROOT / 'godot/content/rules/style_anims.json').write_text(json.dumps(out), encoding='utf-8')
print(len(out), 'styles')


def num(r, i):
    try:
        return int(float(r[i])) if i < len(r) and r[i].strip() != '' else 0
    except ValueError:
        return 0


fx = {r[0].strip(): [num(r, 4), num(r, 5), num(r, 6), num(r, 7), num(r, 8), num(r, 9), num(r, 10)]
      for r in csv.reader(io.StringIO(g['styles.csv'].decode('latin1'))) if len(r) > 10 and r[0].strip().isdigit()}
(ROOT / 'godot/content/rules/style_fx.json').write_text(json.dumps(fx), encoding='utf-8')
print(len(fx), 'style trails')
