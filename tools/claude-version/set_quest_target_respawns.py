"""Named quest kill targets respawn in 5 minutes at most (owner ruling 2026-10-15, quest probe hand-off).

Every Mob row whose name is the target of a DataQuest kill step (StepType 0 Kill / 1 KillFinish, TargetName "name;region"),
that is a named monster (the name starts with a capital), below level 55, and respawns after more than 300 seconds or on
the server default (RespawnInterval 0: a named monster's default is 10-15 minutes), gets RespawnInterval 300. Realm guards
that share a target's name (Guardian, Guardsman; ClassType *Guard*) are left alone. The quest probe listed 153 such
targets; this finds 155 names (it also catches Aricoer and Rat-catcher).

The old values go into set_quest_target_respawns.ledger.json for rollback.

  python set_quest_target_respawns.py            # server stopped; backs up the DB, sets 300, asserts the row count
  python set_quest_target_respawns.py --dry-run  # list what would change
  python set_quest_target_respawns.py rollback   # restores every value from the ledger
"""
import collections, datetime, json, os, shutil, sqlite3, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB = os.path.join(ROOT, "runtime", "data", "opendaoc.sqlite3.db")
LEDGER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "set_quest_target_respawns.ledger.json")
MAX_SECONDS = 300


def targets(con):
    found = collections.defaultdict(set)
    for qid, step_types, target_names in con.execute("select ID, StepType, TargetName from DataQuest"):
        types, names = (step_types or "").split("|"), (target_names or "").split("|")
        for i, kind in enumerate(types):
            if kind.strip() in ("0", "1") and i < len(names) and names[i].strip():
                name, _, region = names[i].partition(";")
                found[(name.strip(), region.strip())].add(qid)
    return found


def rows_to_change(con):
    rows = {}
    for (name, region), _ in targets(con).items():
        sql = "select Mob_ID, Name, Region, Level, RespawnInterval, ClassType from Mob where Name=?" + (" and Region=?" if region else "")
        for mob_id, mob_name, mob_region, level, respawn, class_type in con.execute(sql, (name, int(region)) if region else (name,)):
            if not mob_name[:1].isupper() or level >= 55 or "Guard" in (class_type or ""):
                continue
            if respawn > MAX_SECONDS or respawn == 0:
                rows[mob_id] = (mob_name, mob_region, level, respawn)
    return rows


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "apply"
    if action == "--dry-run":
        con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
        rows = rows_to_change(con)
        print(f"{len(rows)} rows, {len({r[0] for r in rows.values()})} names")
        for mob_id, (name, region, level, respawn) in sorted(rows.items(), key=lambda kv: kv[1]):
            print(f"  {name} (region {region}, level {level}): {respawn} s -> {MAX_SECONDS} s")
        sys.exit()
    if "coreserver" in subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower():
        sys.exit("CoreServer is running; stop the server first.")
    backup = DB.replace(".db", f".before-quest-respawns-{action}-{datetime.datetime.now():%Y%m%d-%H%M%S}.db")
    shutil.copy2(DB, backup)
    print("backup", backup)
    con = sqlite3.connect(DB)
    try:
        if action == "rollback":
            ledger = json.load(open(LEDGER))
            n = 0
            for mob_id, old in ledger["rows"].items():
                n += con.execute("update Mob set RespawnInterval=? where Mob_ID=? and RespawnInterval=?", (old, mob_id, MAX_SECONDS)).rowcount
            assert n == len(ledger["rows"]), (n, len(ledger["rows"]))
            con.commit()
            print(f"restored {n} rows")
            sys.exit()
        assert not os.path.exists(LEDGER), "already applied (see the ledger); roll back first"
        rows = rows_to_change(con)
        n = 0
        for mob_id in rows:
            n += con.execute("update Mob set RespawnInterval=? where Mob_ID=?", (MAX_SECONDS, mob_id)).rowcount
        assert n == len(rows), (n, len(rows))
        con.commit()
        json.dump({"applied": datetime.datetime.now().isoformat(), "rows": {k: v[3] for k, v in rows.items()},
                   "names": sorted({v[0] for v in rows.values()})}, open(LEDGER, "w"), indent=1)
        print(f"set {n} rows ({len({v[0] for v in rows.values()})} names) to {MAX_SECONDS} s; ledger {LEDGER}")
    finally:
        con.close()
