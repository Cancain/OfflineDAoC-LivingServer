"""Move Princess Nahemah's Darkness Falls spawn off her dais onto the connected floor in front of it (2026-10-13).

Her dais (18,329 / 24,840, height 17,246) is a navmesh island of its own (navcomp area 9873, 0.0% of the zone,
joined to nothing): every path toward her stops short and the raid's approach point below the dais has no line of
sight, so bot raids never damaged her and skipped her at 100% ("no damage for five minutes", 2026-10-12, twice).
The new spot (18,560 / 24,840 / 17,203) is on the main floor (area 20842) in front of the dais, with a complete
path and line of sight from the raid approach. Heading unchanged. The DF raid manifest
(GameServer/bots/autonomous/data/darkness_falls_raid_event_mobs.json) must carry the same coordinates: its rows
are checked exactly at startup (a mismatch closes every Darkness Falls route).

  python move_princess_nahemah.py            # server stopped; backs up the DB, moves the row, asserts one row
  python move_princess_nahemah.py rollback   # puts her back on the dais (manifest must be reverted too)
"""
import datetime, os, shutil, sqlite3, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB = os.path.join(ROOT, "runtime", "data", "opendaoc.sqlite3.db")
MOB_ID = "eff810dc-0517-4265-9fe0-1517e2b0b419"
DAIS = (18329, 24840, 17246)
FLOOR = (18560, 24840, 17203)

if "coreserver" in subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower():
    sys.exit("CoreServer is running; stop the server first.")
src, dst = (FLOOR, DAIS) if len(sys.argv) > 1 and sys.argv[1] == "rollback" else (DAIS, FLOOR)
backup = DB.replace(".db", f".before-nahemah-move-{datetime.datetime.now():%Y%m%d-%H%M%S}.db")
shutil.copy2(DB, backup)
print("backup", backup)
con = sqlite3.connect(DB)
try:
    row = con.execute("select Name, Region, X, Y, Z from Mob where Mob_ID=?", (MOB_ID,)).fetchone()
    assert row and row[0] == "Princess Nahemah" and row[1] == 249 and tuple(row[2:]) == src, row
    cur = con.execute("update Mob set X=?, Y=?, Z=? where Mob_ID=?", (*dst, MOB_ID))
    assert cur.rowcount == 1, cur.rowcount
    con.commit()
finally:
    con.close()
print("Princess Nahemah", src, "->", dst)
