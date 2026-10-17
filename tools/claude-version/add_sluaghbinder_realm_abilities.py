"""Sluaghbinder realm abilities (owner 2026-10-13). The class (63) had none. It gets the standard list of a hybrid
melee/pet class, modelled on the Reaver (a dark-magic melee hybrid with a shield) without Mastery of Parrying (the class
has no parry) and Armor of Faith, plus the pet classes' Wild Minion, and its own Crippling Plague
(AtlasOF_CripplingPlague: instant, 1 minute recast, a 10-second slow from 10% to 95%, then a small poison burst).
No Mastery of Concentration, Raging Power or Ethereal Bond: the pure casters' power abilities would make it too strong.

    python add_sluaghbinder_realm_abilities.py     (server stopped; backs up the database first; safe to rerun)"""
import datetime, os, sqlite3, subprocess, sys

# <playable>/tools/claude-version -> <playable>/runtime/data/opendaoc.sqlite3.db
DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "runtime", "data", "opendaoc.sqlite3.db")
CLASS = 63
PLAGUE = dict(KeyName="AtlasOF_CripplingPlague", Name="Crippling Plague",
              Description="Instant plague on an enemy: it slows the target by 10%, rising every second to 95% over 10 seconds, "
                          "then bursts for 150 poison damage to enemies within 250 units of the target. Curing it first stops "
                          "the burst. 1 minute reuse.",
              IconID=3425, Implementation="DOL.GS.RealmAbilities.AtlasOF_CripplingPlague")
ABILITIES = ["AtlasOF_AugStr", "AtlasOF_MasteryOfArms", "AtlasOF_AugDex", "AtlasOF_MasteryOfPain", "AtlasOF_MasteryOfBlocking",
             "AtlasOF_HailOfBlows", "AtlasOF_AugCon", "AtlasOF_SecondWind", "AtlasOF_AugQui", "AtlasOF_AugAcuity",
             "AtlasOF_Serenity", "AtlasOF_WildArcana", "AtlasOF_LongWind", "AtlasOF_Tireless", "AtlasOF_Regeneration",
             "AtlasOF_Toughness", "AtlasOF_DeterminationHybrid", "AtlasOF_MasteryOfWater", "AtlasOF_AvoidanceOfMagic",
             "AtlasOF_Lifter", "AtlasOF_VeilRecovery", "AtlasOF_FirstAid", "AtlasOF_IgnorePain", "AtlasOF_RainOfFire",
             "AtlasOF_RainOfIce", "AtlasOF_RainOfAnnihilation", "AtlasOF_EmptyMind", "AtlasOF_Purge", "AtlasOF_WildMinion",
             "AtlasOF_CripplingPlague"]


def main():
    if "coreserver" in subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower():
        sys.exit("CoreServer is running; stop the server first.")
    con = sqlite3.connect(DB)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    bk = sqlite3.connect(os.path.join(os.path.dirname(DB), f"opendaoc.sqlite3.before-sluaghbinder-ras-{stamp}.db"))
    con.backup(bk)
    bk.close()
    now = "2000-01-01 00:00:00"
    con.execute("begin")
    row = con.execute("select AbilityID from Ability where KeyName=?", (PLAGUE["KeyName"],)).fetchone()
    if row:
        con.execute("update Ability set Name=?, Description=?, IconID=?, Implementation=? where KeyName=?",
                    (PLAGUE["Name"], PLAGUE["Description"], PLAGUE["IconID"], PLAGUE["Implementation"], PLAGUE["KeyName"]))
    else:
        aid, iid = con.execute("select max(AbilityID) + 1, max(InternalID) + 1 from Ability").fetchone()
        con.execute("insert into Ability (AbilityID, KeyName, Name, InternalID, Description, IconID, Implementation, LastTimeRowUpdated) "
                    "values (?,?,?,?,?,?,?,?)", (aid, PLAGUE["KeyName"], PLAGUE["Name"], iid, PLAGUE["Description"], PLAGUE["IconID"],
                                                 PLAGUE["Implementation"], now))
    known = {r[0] for r in con.execute("select KeyName from Ability")}
    missing = [k for k in ABILITIES if k not in known]
    assert not missing, missing
    con.execute("delete from ClassXRealmAbility_Atlas where CharClass=?", (CLASS,))
    for n, key in enumerate(ABILITIES):
        con.execute("insert into ClassXRealmAbility_Atlas (CharClass, AbilityKey, LastTimeRowUpdated, ClassXRealmAbility_Atlas_ID) "
                    "values (?,?,?,?)", (CLASS, key, now, f"Sluaghbinder1-{n // 10}-{n % 10}"))
    assert con.execute("select count(*) from ClassXRealmAbility_Atlas where CharClass=?", (CLASS,)).fetchone()[0] == len(ABILITIES)
    con.commit()
    con.close()
    print(f"Sluaghbinder: {len(ABILITIES)} realm abilities, including {PLAGUE['Name']}")


if __name__ == "__main__":
    main()
