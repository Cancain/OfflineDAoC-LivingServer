"""The 1.65 task system's data (owner 2026-10-10: "make sure the original /task system is in place ... and works on
guards ... how often you could get tasks").

How it worked (period: Camelot Warcry "Task guide", Oct 2004, archived in the period data):
  - two kinds, kill tasks and delivery tasks, levels 1 to 19 only ("At level 20, you will no longer be able to task");
  - delivery tasks from non-guard NPCs: target one, /say task; not every NPC has one ("normally at least ONE NPC in
    town will give you a delivery task"); you get an item to hand to an NPC elsewhere, for experience / money;
  - kill tasks from named guards; the guard names the monster and its general direction, you kill it and right-click
    the same guard ("about triple a yellow kill experience"). The guide says only one or two named guards per level
    had them; the owner (2026-10-10) chose any named guard whose zone has a valid target instead;
  - "You are limited to the number of kill tasks you can do per level by your level" (level 12: 12 that level);
  - a task fails when its two hours run out or you die, and a failed one still counts against that level.
The old server's task code (development-source quests/Tasks, read-only reference) gives the rest: named-guard test
(KillTask.CheckNamedGuard), the kill target (a monster of the guard's zone, level L-2 .. L, a common lower-case
name), the money tables, the experience (AbstractTask.RewardXP), the 35% delivery chance and the 5-minute wait after a
refusal (task_pause_ticks), the generated delivery items.

Writes godot/content/quests/tasks.json.   python build_tasks.py"""
import csv, io, json
from pathlib import Path
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk

OUT = ROOT / 'godot/content/quests/tasks.json'
MAX_LEVEL = 19                                   # period: tasks from level 1 through 19

# old server tables (quests/Tasks): copper by level 1..20
KILL_MONEY = [28, 57, 77, 105, 140, 190, 257, 347, 470, 632, 735, 852, 987, 1147, 1330, 1542, 1790, 2077, 2407, 2801]
DELIVERY_MONEY = [25, 34, 46, 63, 84, 114, 154, 208, 282, 379, 441, 511, 592, 688, 798, 925, 1074, 1246, 1444, 1830]
DELIVERY_FORMATS = ["{0}'s {1} {2}", "{1} {2} of {0}"]
DELIVERY_SIZES = ["Little", "Small", "Large", "Big", "Thin"]          # the old list's "Thin2" is a typo for Thin
DELIVERY_OBJECTS = ["Potion", "Flask", "Necklace", "Ring", "Dyes", "Green Gem", "Note", "Scroll", "Book", "Hammer",
                    "Crown", "Blue orb", "Red orb", "Silver orb", "Wand", "Bottle", "Gold key", "Silver key", "Mirror",
                    "Scroll tube", "Four leaf clover", "Vine", "Silver earring", "Gold bracelet", "Gold necklace",
                    "Amulet", "Letter"]
DELIVERY_MODELS = [99, 99, 101, 103, 229, 113, 498, 499, 500, 510, 511, 523, 524, 606, 552, 554, 583, 584, 592, 603,
                   607, 611, 621, 622, 623, 101, 498]


def main():
    g = read_mpk(str(CLIENT / 'gamedata.mpk'))
    objects = {r[0].strip(): r for r in csv.reader(io.StringIO(g['objects.csv'].decode('latin1'))) if r and r[0].strip().isdigit()}
    icons = {str(m): int(objects[str(m)][3]) for m in set(DELIVERY_MODELS) if str(m) in objects and objects[str(m)][3].strip().isdigit()}
    OUT.write_text(json.dumps({
        'source': 'Camelot Warcry Task guide (2004) + old server quests/Tasks (see pipeline/build_tasks.py)',
        'max_level': MAX_LEVEL, 'expire_s': 7200, 'pause_s': 300, 'delivery_chance': 35,
        'kill_money': KILL_MONEY, 'delivery_money': DELIVERY_MONEY,
        'delivery_items': {'formats': DELIVERY_FORMATS, 'sizes': DELIVERY_SIZES, 'objects': DELIVERY_OBJECTS,
                           'models': DELIVERY_MODELS, 'icons': icons}
        }, indent=1), encoding='utf-8')
    print('wrote', OUT)


if __name__ == '__main__':
    main()
