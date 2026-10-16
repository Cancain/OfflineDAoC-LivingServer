"""1.65 Necromancer and Bonedancer pet looks (owner 2026-10-13, from the legacy Offline DAoC Rebuilt project's pet
appearance ledger). Every model is in the real 1.64 retail client; the freeshard ones they replace (2073, 2176, 2177,
2186, 2220 and the bone items 3461-3469) are later additions.

Necromancer: zombie servants model 110, reanimated servant 467, necroservant 106, greater necroservant 440, all with
nothing in hand; abomination 653 with its two-handed sword (equipment set abomination_old: item 6, colour 74, effect 30).
Bonedancer: commanders model 952 with no shield and no helm (their weapon, one of nine plain Norse weapons, comes from
CommanderPet); minions keep model 920 and get Norse weapons in code (BdSubPet); the template equipment below only covers
what the code does not: casters' staff 327 + robe 683, archers' short sword 311 + bow 564 + leather 300/303/304, guardians'
hammer 321, debuffers' short sword 311, healers' and melee minions' leather set (bd_armor).

    python set_165_pet_models.py     (server stopped; backs up the database first; safe to rerun)"""
import datetime, os, sqlite3, subprocess, sys

# <playable>/tools/claude-version -> <playable>/runtime/data/opendaoc.sqlite3.db
DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "runtime", "data", "opendaoc.sqlite3.db")
TEMPLATES = {  # TemplateId: (Model, EquipmentTemplateID)
    200: ("110", ""), 201: ("110", ""), 202: ("110", ""), 203: ("467", ""), 204: ("106", ""), 205: ("440", ""),
    206: ("653", "abomination_old"),
    49: ("952", ""), 50: ("952", ""), 51: ("952", ""), 52: ("952", ""),
    **{t: ("920", "bd_mage") for t in range(53, 59)},
    **{t: ("920", "10:311") for t in range(59, 65)},
    **{t: ("920", "10:321") for t in range(65, 71)},
    **{t: ("920", "bd_armor") for t in range(71, 77)},
    **{t: ("920", "bd_archer") for t in range(77, 83)},
    **{t: ("920", "bd_armor") for t in range(83, 89)},
}
EQUIPMENT = {  # (set, slot): model
    ("bd_mage", 12): 327, ("bd_mage", 25): 683,
    ("bd_archer", 10): 311, ("bd_archer", 13): 564, ("bd_archer", 22): 303, ("bd_archer", 23): 304, ("bd_archer", 25): 300,
    ("bd_armor", 22): 303, ("bd_armor", 23): 304, ("bd_armor", 25): 300,
    ("abomination_old", 12): 6,
}


def main():
    if "coreserver" in subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower():
        sys.exit("CoreServer is running; stop the server first.")
    con = sqlite3.connect(DB)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bk = sqlite3.connect(os.path.join(os.path.dirname(DB), f"opendaoc.sqlite3.before-165-pet-models-{stamp}.db"))
    con.backup(bk)
    bk.close()
    con.execute("begin")
    for tid, (model, equipment) in TEMPLATES.items():
        assert con.execute("update NpcTemplate set Model=?, EquipmentTemplateID=? where TemplateId=?", (model, equipment, tid)).rowcount == 1, tid
    for (name, slot), model in EQUIPMENT.items():
        assert con.execute("update NPCEquipment set Model=? where TemplateID=? and Slot=?", (model, name, slot)).rowcount == 1, (name, slot)
    # the abomination's sword: colour 74, effect 30 ("univ 2h/gr white core red glow")
    assert con.execute("update NPCEquipment set Color=74, Effect=30 where TemplateID='abomination_old' and Slot=12").rowcount == 1
    con.commit()
    print(f"{len(TEMPLATES)} pet templates and {len(EQUIPMENT)} equipment slots set to the 1.65 looks")


if __name__ == "__main__":
    main()
