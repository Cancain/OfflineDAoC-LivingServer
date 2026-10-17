"""The style number in the server's combat packets -> the style's animation (0.36c).

CombatAnimation carries the style's Icon (or, with a two-handed weapon, its TwoHandAnimation) - a gamedata styles.csv
row; that row's Animation column is the canims.csv animation (content/characters/style_clips.json names its clip),
the lookup the client made. Writes godot/content/rules/style_anims.json {styles.csv id: animation}.

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
