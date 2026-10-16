"""Build many zones in one go, each through the whole ZONE CONTENT PROCESS chain, one after another (one GPU job:
the Real-ESRGAN upscales run inside build_zone / build_monsters):

    python build_world.py 201 202 203 ...        # zones (terrain or city)
    python build_world.py --hibernia              # every 1.65 Hibernian outdoor zone not built yet

Per zone: build_zone.py, build_npcs.py, build_monsters.py, build_merchants.py, build_quests.py, build_sounds.py. At the end
build_armor.py and build_weapons.py (the new NPCs' equipment). A zone that fails is logged and the rest go on.
Log: assets/build_world.log (appended)."""
import subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT

LOG = ROOT / 'assets/build_world.log'
# 1.65 Hibernia outdoors: the classic realm (region 200, the old frontiers included) and Shrouded Isles (region 181).
# Housing (region 202, 1.68) is not 1.65; dungeons (zones.dat type 2) need the dungeon builder.
HIBERNIA = [201, 202, 203, 204, 205, 206, 207, 208, 210, 211, 212, 214, 216, 181, 182, 183, 184, 185, 186, 187,
            221, 222, 223, 224, 249, 180, 190, 191, 247, 250, 251, 252, 253]     # + dungeons, DF, SI dungeons, battlegrounds
# Classic + Shrouded Isles only (the DB's Regions.Expansion 0 / 1); no housing (1.71), tutorials or New Frontiers
ALBION = [0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 14, 15, 26, 19, 21, 22, 23, 24, 50, 51, 52, 53, 54, 55, 56, 57, 60, 61, 62,
          233, 244, 245]
MIDGARD = [100, 101, 102, 103, 104, 105, 106, 107, 108, 111, 112, 113, 115, 116, 120, 125, 126, 127, 128, 129, 150, 151,
           152, 153, 154, 155, 156, 158, 160, 161, 246]


def run(args, zone):
    t0 = time.time()
    p = subprocess.run([sys.executable] + args, cwd=HERE, capture_output=True, text=True)
    tail = (p.stdout.strip().splitlines() or [''])[-1][:300]
    line = f"{time.strftime('%H:%M:%S')} zone {zone} {args[0]} rc={p.returncode} {time.time() - t0:.0f}s  {tail}"
    if p.returncode != 0:
        line += '\n    ' + '\n    '.join(p.stderr.strip().splitlines()[-6:])
    with open(LOG, 'a', encoding='utf-8') as f:
        f.write(line + '\n')
    print(line, flush=True)
    return p.returncode == 0


def main():
    zones = [int(a) for a in sys.argv[1:] if a.isdigit()]
    for flag, lst in (('--albion', ALBION), ('--midgard', MIDGARD)):
        if flag in sys.argv:
            zones += [z for z in lst if not (ROOT / f'godot/content/zones/zone{z:03d}/zone.json').exists()]
    if '--hibernia' in sys.argv:
        zones += [z for z in HIBERNIA if not (ROOT / f'godot/content/zones/zone{z:03d}/zone.json').exists()]
    for z in zones:
        if not run(['build_zone.py', str(z)], z):
            continue
        for step in ('build_npcs.py', 'build_monsters.py', 'build_merchants.py', 'build_quests.py'):
            run([step, f'--zone={z}'], z)
        run(['build_sounds.py', str(z)], z)
    run(['build_zone_index.py'], 'all')                  # zones' places in their regions (border crossing)
    run(['build_armor.py'], 'all')
    run(['build_weapons.py'], 'all')
    print('world build done', flush=True)


if __name__ == '__main__':
    main()
