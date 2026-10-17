"""relic_players_required_on_pad 16 -> 8 (owner 2026-10-15, option 3: lower it AND count a player's companion bots).

A relic on an enemy pad can be taken only with this many enemies of the keep's realm within 500 units of the pad
(GameRelic.PickupCore / GameRelicPad.GetEnemiesOnPad). 16 is a live-server number; offline, a player with companions
could never reach it. The code default (ServerProperties.cs) is 8 too, but an existing database keeps its stored value,
so this updates the row.

  python set_relic_pad_requirement.py            # server stopped; backs up the DB, sets 8, asserts one row
  python set_relic_pad_requirement.py rollback   # back to 16
"""
import datetime, os, shutil, sqlite3, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB = os.path.join(ROOT, "runtime", "data", "opendaoc.sqlite3.db")
KEY = "relic_players_required_on_pad"

if "coreserver" in subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower():
    sys.exit("CoreServer is running; stop the server first.")
old, new = ("8", "16") if len(sys.argv) > 1 and sys.argv[1] == "rollback" else ("16", "8")
backup = DB.replace(".db", f".before-relic-pad-{datetime.datetime.now():%Y%m%d-%H%M%S}.db")
shutil.copy2(DB, backup)
print("backup", backup)
con = sqlite3.connect(DB)
try:
    row = con.execute('select Value, DefaultValue from ServerProperty where "Key"=?', (KEY,)).fetchone()
    assert row and row[0] == old, row
    cur = con.execute('update ServerProperty set Value=?, DefaultValue=? where "Key"=?', (new, new, KEY))
    assert cur.rowcount == 1, cur.rowcount
    con.commit()
    print(f"{KEY}: {old} -> {new}")
finally:
    con.close()
