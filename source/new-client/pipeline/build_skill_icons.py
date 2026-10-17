"""Skill icons for the server's skill lists (Offline DAoC Rebuilt, owner 2026-10-11).

The server's skill packets (VariousUpdate 1 / 2) carry each skill's icon number the way the client reads it: a spell's
through spells.csv, a style's through styles.csv, then icons.csv gives the sheet icon and its border overlay - the
same lookup build_classes.py makes for the game's own lists. Abilities and specializations carry an icons.csv id.
Writes godot/content/rules/skill_icons.json: {"spell": {n: [icon, border]}, "style": {...}, "icon": {...}}.

    python pipeline/build_skill_icons.py
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

OUT = ROOT / 'godot/content/rules/skill_icons.json'


def main():
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    tab = lambda n: {r[0].strip(): r for r in csv.reader(io.StringIO(g[n].decode('latin1'))) if r and r[0].strip().isdigit()}
    icons, csp, cst = tab('icons.csv'), tab('spells.csv'), tab('styles.csv')
    num = lambda v, d: int(v) if v.strip().lstrip('-').isdigit() else d

    def resolve(icon_id):
        r = icons.get(str(icon_id).strip())
        return [num(r[2], 0), num(r[3], -1)] if r else [0, -1]
    out = {'spell': {k: resolve(r[2]) for k, r in csp.items() if len(r) > 2},
           'style': {k: resolve(r[2]) for k, r in cst.items() if len(r) > 2},
           'icon': {k: resolve(k) for k in icons}}
    OUT.write_text(json.dumps(out), encoding='utf-8')
    print({k: len(v) for k, v in out.items()})


if __name__ == '__main__':
    main()
