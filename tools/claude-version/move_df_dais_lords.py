"""Move High Lord Saeor and High Lord Oro off their Darkness Falls daises onto the connected floor in front (2026-10-13).

Same fault as Princess Nahemah (move_princess_nahemah.py): each dais is a navmesh island of its own (navcomp areas of
about 103,000 square units, joined to nothing, 43-45 units above the floor). The nearest main floor is 150-200 units
away, so a melee raider (reach 200) on the floor never reaches the lord, and paths onto the dais fail. The autonomous
raid dropped Saeor as an unreachable target (run 2026-10-13: "AUTONOMOUS_UNREACHABLE_TARGET ... heightAbove=168-276")
and skipped Oro at 100% ("no damage for five minutes", 2026-10-12), so Darkness Falls never reached Legion.

The new spots are on the main floor (area 20842), 175-200 units in front of each dais on the raid's approach side:
  Saeor 49,971 / 38,134 / 15,969  ->  49,796 / 38,134 / 15,925 (west)
  Oro   45,048 / 25,015 / 15,967  ->  45,048 / 25,215 / 15,924 (south, beside the old raid front 44,948 / 25,188)
Headings unchanged; Oro's two clones already stand on the floor. The DF raid manifest
(GameServer/bots/autonomous/data/darkness_falls_raid_event_mobs.json) carries the same coordinates: its rows are
checked exactly at startup (a mismatch closes every Darkness Falls route).

  python move_df_dais_lords.py            # server stopped; backs up the DB, moves both rows, asserts one row each
  python move_df_dais_lords.py rollback   # puts them back on the daises (manifest must be reverted too)
"""
import datetime, os, shutil, sqlite3, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB = os.path.join(ROOT, "runtime", "data", "opendaoc.sqlite3.db")
MOVES = [  # (Mob_ID, name, dais, floor)
    ("4552e0a1-132c-4f06-89b8-2fe3406514de", "High Lord Saeor", (49971, 38134, 15969), (49796, 38134, 15925)),
    ("504d573f-deab-4cb2-9dbc-d9d053d7af2f", "High Lord Oro", (45048, 25015, 15967), (45048, 25215, 15924)),
]

if "coreserver" in subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower():
    sys.exit("CoreServer is running; stop the server first.")
rollback = len(sys.argv) > 1 and sys.argv[1] == "rollback"
backup = DB.replace(".db", f".before-df-dais-lords-{datetime.datetime.now():%Y%m%d-%H%M%S}.db")
shutil.copy2(DB, backup)
print("backup", backup)
con = sqlite3.connect(DB)
try:
    for mob_id, name, dais, floor in MOVES:
        src, dst = (floor, dais) if rollback else (dais, floor)
        row = con.execute("select Name, Region, X, Y, Z from Mob where Mob_ID=?", (mob_id,)).fetchone()
        assert row and row[0] == name and row[1] == 249 and tuple(row[2:]) == src, row
        cur = con.execute("update Mob set X=?, Y=?, Z=? where Mob_ID=?", (*dst, mob_id))
        assert cur.rowcount == 1, cur.rowcount
        print(name, src, "->", dst)
    con.commit()
finally:
    con.close()
