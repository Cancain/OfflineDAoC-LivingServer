"""Adds the styles.csv trail columns to the built styles.json without rebuilding every class file (owner 2026-10-10:
the style colour flash). build_classes.py writes the same fields on a full build."""
import csv, io, json
from pathlib import Path
from daoc_mpk import read_mpk
from assets_pipeline import CLIENT
from build_classes import style_trail

OUT = Path(__file__).resolve().parent.parent / 'godot/content/classes/styles.json'
g = read_mpk(str(CLIENT / 'gamedata.mpk'))
cst = {r[0].strip(): r for r in csv.reader(io.StringIO(g['styles.csv'].decode('latin1'))) if r and r[0].strip().isdigit()}
styles = json.loads(OUT.read_text(encoding='utf-8'))
done = 0
for st in styles.values():
    row = cst.get(str(st.get('icon') or 0))
    row2 = cst.get(str(st.get('twohandanimation') or 0))
    st['trail'], st['trail_2h'] = style_trail(row), style_trail(row2 or row)
    done += st['trail'] is not None
OUT.write_text(json.dumps(styles, separators=(',', ':')), encoding='utf-8')
print(f'{done} of {len(styles)} styles have a trail row')
