"""Item dye colours for the 0.36c client (owner 2026-10-11: armour drew in its plain undyed cloth).

An item's Color (the server sends it with every item) is a row of the client's gamedata tints.csv: ID, name, then the
colour for classic, expansion and Catacombs models. The game's figures are Catacombs (fig3), so the Cata colour is
used; the client multiplies the part's texture by it. Writes godot/content/rules/dye_tints.json {id: [r, g, b] 0..1}.

    python pipeline/build_dye_tints.py
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


def main():
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    out = {}
    for r in csv.reader(io.StringIO(g['tints.csv'].decode('latin1'))):
        if not r or not r[0].strip().isdigit():
            continue
        vals = [v.strip() for v in r[2:11]]
        rgb = vals[6:9] if len(vals) >= 9 and all(v.isdigit() for v in vals[6:9]) else vals[0:3]
        if all(v.isdigit() for v in rgb):
            out[r[0].strip()] = [round(int(v) / 255.0, 4) for v in rgb]
    (ROOT / 'godot/content/rules/dye_tints.json').write_text(json.dumps(out), encoding='utf-8')
    print(len(out), 'dyes;', {k: out.get(k) for k in ('10', '17', '19', '20', '22', '33')})


if __name__ == '__main__':
    main()
