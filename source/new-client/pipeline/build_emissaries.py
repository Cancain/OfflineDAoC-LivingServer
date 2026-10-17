"""The three faction emissaries (owner 2026-10-09: "add our 3 custom emissarie reputation repeatable quests npcs in
their spots beside them as the only 3 custom npcs we've added" - THE ONLY NON-1.65 NPCs in the game). The old
project's own design (FactionEmissaryRuntime.cs / FactionReputationQuest.cs / FactionReputationTargets.cs, read only,
rules + text rebuilt here):
  - one emissary per realm beside a Shrouded Isles faction stable master: Kzzirrak (Krrzck, by Zrrazk in Necht),
    Ysslith (Cryptos Mythicos, by Vilmalin in Caer Diogel), Hrodvar Deepvow (The Remnants, by Korlis in Hagall);
  - the repeatable hunt: kill 10 of one common enemy species of the faction (outdoor, no-realm, respawning,
    lower-case-named DB mobs of an enemy faction in the realm's SI region; species with 5+ spawns first), at the
    level nearest yours without going over (cap 45) plus up to 3 below; any of that name in the region counts;
  - turn in: faction aggro -10 (+5 for a rerolled hunt); the hunted species' own faction +same if its base is above
    75 and the two are enemies; rerolls are free but halve the reward until turned in.
Writes godot/content/quests/emissaries.json.

    python build_emissaries.py"""
import json, math, re, sqlite3
from collections import defaultdict
from assets_pipeline import ROOT
from build_zone import zone_section
from build_items import DB

OUT = ROOT / 'godot/content/quests/emissaries.json'
DEFAULT_NPC = 'DOL.GS.GameNPC'
REQUIRED, FULL, REROLLED, LEVEL_CAP, WINDOW, MIN_SPAWNS = 10, 10, 5, 45, 3, 5

# FactionEmissaryRuntime.Definitions: realm, faction, hunt region, name, region, x, y, z, model, size, gender, host,
# town, mounts, fixed heading
DEFS = [
    (3, 89, 181, 'Kzzirrak', 181, 427497, 316775, 3417, 684, 45, 0, 'Zrrazk', 'Necht', 'wyverns', None),
    (1, 16, 51, 'Ysslith', 51, 400261, 503487, 4665, 829, 51, 2, 'Vilmalin', 'Caer Diogel', 'dragonflies', None),
    (2, 172, 151, 'Hrodvar Deepvow', 151, 380304, 383359, 7754, 187, 50, 1, 'Korlis', 'Hagall', 'gryphons', 2590),
]
# the emissaries' own words (FactionEmissaryRuntime: Story, Greeting, GatedStablesLine, HowItWorks, Progress, Ready,
# PaidLine, the stable refusal); {standing} {hunt} {target} {half} are filled in at run time
TEXT = {
    3: {'story': "The Krrzck Hive guards the wyvern roads to Krrzck and Mantid Town. Strangers ride only when the Hive trusts them, and the Hive trusts only those who kill its enemies.",
        'gated': "Zrrazk here, Dalniver at Krrzck and Calvine in Mantid Town carry only softskins the Hive trusts.",
        'greeting': "Click-click. Softskin stands before Kzzirrak, voice of the Krrzck Hive. {gated} Softskin wants trust? Then softskin [hunts for the Hive], or asks how [trust grows]. {standing}",
        'hunt_words': ['hunts for the hive', 'hunt'], 'how_words': ['trust grows'],
        'how': "The Hive remembers deeds, not words. Ten enemies of the Hive fall, softskin returns, Hive trust grows ten. Rot-growth botonids and Olcasgean's twisted ones, the Hive hates them all. At -50 or better, the Hive's wyverns carry softskin.",
        'progress': "Zzt. Softskin hunts {hunt}. The Hive waits. Ask to [show location], or [reroll] for other prey; the Hive gives only half trust for chosen prey.{half}",
        'ready': "Kzzirrak tastes the air. Ten {target} are dead. [Claim reward] and the Hive remembers.",
        'paid': "Click... click. The Hive remembers softskin's hunt. Come again. There is always more rot to cut.",
        'refusal': "{master} rattles its mandibles and turns away."},
    1: {'story': "The lammia of the Cryptos Mythicos keep the dragonfly roads between Clifton, the Lammia Camp and Caer Diogel. They carry only those who have bled their enemies.",
        'gated': "Vilmalin carriesss anyone to Clifton, but Nimea there and Callisa at the Lammia Camp ssserve only those we trust.",
        'greeting': "Ssso... a warm-blood comes to Ysslith. {gated} Earn our favor: [hunt for the Cryptos], or ask how [favor is earned]. {standing}",
        'hunt_words': ['hunt for the cryptos', 'hunt'], 'how_words': ['favor is earned'],
        'how': "We remember what is done for us, little warm-blood. Ssslay ten of our enemies, the Kulaclan orcs, the thrawn ogres, Morgana's restless dead, and return. Each hunt earns ten favor. At -50 or better, Nimea and Callisa will ssserve you.",
        'progress': "Ssstill hunting? {hunt}. Ask to [show location], or [reroll] if the prey displeases you; chosen prey earns only half favor.{half}",
        'ready': "Mmm, I can ssmell their blood on you. Ten {target}. [Claim reward] and I will whisper your name to the others.",
        'paid': "Well done, warm-blood. The Cryptos Mythicos remember. Come back when you hunger for more.",
        'refusal': "{master} hisses softly and will not deal with you."},
    2: {'story': "The Remnants, last of the free iarn dwarf clans, keep the gryphon roads to their camp in Faraheim. They fly only friends, and friends are made by killing the clans' foes.",
        'gated': "Korlis flies any Midgardian to our camp, but Minerva there flies only friends of the clans, and the camp's dwarves strike at strangers.",
        'greeting': "Hmph. Surface-folk. {gated} Want our trust? [Hunt for the Remnants], or ask how [trust is forged]. {standing}",
        'hunt_words': ['hunt for the remnants', 'hunt'], 'how_words': ['trust is forged'],
        'how': "Trust is forged, not bought. Bring down ten of our foes, the morvalt raiders, the Servants of Iarnvidiur, the Skogsra shade seekers, and come back. Ten trust each time. At -50 or better, Minerva will fly you and the camp will let you be.",
        'progress': "Still at it? {hunt}. Ask me to [show location], or [reroll] for other quarry; picky hunters get half the trust.{half}",
        'ready': "Ha! Ten {target} down. [Claim reward] and I'll carve your name on the clan stone.",
        'paid': "Good work. The Remnants don't forget an honest axe. Come back when you're ready for more.",
        'refusal': "{master} crosses their arms and will not saddle a gryphon for you."},
}


def region_zones(region):
    """Zones of a region: id -> (x0, y0, x1, y1, type, name) in region units."""
    out = {}
    for z in range(0, 400):
        sec = zone_section(z)
        if not sec:
            continue
        kv = dict(l.split('=', 1) for l in sec.splitlines() if '=' in l)
        if int(kv.get('region', -1)) != region:
            continue
        x0, y0 = int(kv['region_offset_x']) * 8192, int(kv['region_offset_y']) * 8192
        out[z] = (x0, y0, x0 + int(kv['width']) * 8192, y0 + int(kv['height']) * 8192, int(kv.get('type', 0) or 0),
                  kv.get('name', f'zone{z:03d}').strip())
    return out


def zone_at(zones, x, y):
    for z, (x0, y0, x1, y1, _t, _n) in zones.items():
        if x0 <= x < x1 and y0 <= y < y1:
            return z
    return None


def heading_to(x, y, tx, ty):
    """Point2D.GetHeading: atan2(-dx, dy) in 4096ths of a turn."""
    h = math.atan2(-(tx - x), ty - y) * 4096.0 / (2 * math.pi)
    return int(h + 4096) % 4096 if h < 0 else int(h)


def candidates(db, faction, enemies, region, zones):
    tpl = {r[0]: r[1:] for r in db.execute('select TemplateId, ReplaceMobValues, FactionID, Level from NpcTemplate')}
    groups = defaultdict(list)
    for name, ctype, realm, resp, mid, x, y, z, lvl, tid, fid in db.execute(
            'select Name, ClassType, Realm, RespawnInterval, Mob_ID, X, Y, Z, Level, NPCTemplateID, FactionID '
            'from Mob where Region=?', (region,)):
        if (ctype or '') != DEFAULT_NPC or int(realm or 0) != 0 or int(resp or 0) <= 0 or not (name or '').strip() \
                or name != name.lower() or not (mid or '').strip():
            continue
        zid = zone_at(zones, x, y)
        if zid is None or zones[zid][4] == 2:             # dungeons don't count
            continue
        t = tpl.get(tid)
        owns = bool(t and t[0])
        mf = int((t[1] if owns else fid) or 0)
        if mf not in enemies:
            continue
        levels = [int(v) for v in re.split(r'[;,]', str(t[2] or '')) if v.strip().isdigit() and int(v) > 0] if owns and t[2] else []
        groups[(name, zid)].append((x, y, z, mf, levels or [int(lvl or 0)]))
    out = []
    for (name, zid), mem in groups.items():
        cx, cy = sum(m[0] for m in mem) / len(mem), sum(m[1] for m in mem) / len(mem)
        rep = min(mem, key=lambda m: abs(m[0] - cx) + abs(m[1] - cy))
        lv = sorted(l for m in mem for l in m[4])
        x0, y0 = zones[zid][0], zones[zid][1]
        out.append({'name': name, 'faction': rep[3], 'zone': zid, 'zone_name': zones[zid][5],
                    'pos': [round((rep[0] - x0) * 0.025, 2), round(rep[2] * 0.025, 2), round((rep[1] - y0) * 0.025, 2)],
                    'level': lv[len(lv) // 2], 'min': lv[0], 'max': lv[-1], 'spawns': len(mem)})
    out.sort(key=lambda c: (c['level'], c['name']))
    return out


def main():
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    rules = json.loads((ROOT / 'godot/content/rules/rules.json').read_text(encoding='utf-8'))['factions']
    out = {}
    for realm, fid, hunt_region, name, region, x, y, z, model, size, gender, host, town, mounts, heading in DEFS:
        zones = region_zones(region)
        zid = zone_at(zones, x, y)
        h = db.execute('select X, Y from Mob where Region=? and Name=?', (region, host)).fetchone()
        if heading is None:
            heading = heading_to(x, y, h[0], h[1]) if h else 0
        fac = rules[str(fid)]
        enemies = {int(e) for e in fac['enemies'] if int(e) != fid}
        cands = candidates(db, fid, enemies, hunt_region, zones if hunt_region == region else region_zones(hunt_region))
        x0, y0 = zones[zid][0], zones[zid][1]
        out[str(realm)] = {
            'name': name, 'guild': f"{fac['name']} Emissary", 'faction': fid, 'faction_name': fac['name'],
            'zone': zid, 'pos': [round((x - x0) * 0.025, 3), round(z * 0.025, 3), round((y - y0) * 0.025, 3)],
            'heading': heading, 'model': str(model), 'size': size, 'gender': gender, 'host': host, 'town': town,
            'mounts': mounts, 'text': TEXT[realm], 'candidates': cands,
            # where a kill counts: the hunt region's outdoor zones (FactionTargetCandidate.Matches)
            'hunt_zones': sorted(k for k, v in (zones if hunt_region == region else region_zones(hunt_region)).items() if v[4] != 2)}
        print(name, 'zone', zid, 'heading', heading, '|', len(cands), 'candidate species,',
              sum(1 for c in cands if c['spawns'] >= MIN_SPAWNS), 'common')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        'emissaries': out, 'required': REQUIRED, 'full_gain': FULL, 'rerolled_gain': REROLLED, 'level_cap': LEVEL_CAP,
        'level_window': WINDOW, 'min_spawns': MIN_SPAWNS, 'stable_trust': 50, 'talk_range_units': 600,
        'source': "the old project's FactionEmissaryRuntime / FactionReputationQuest / FactionReputationTargets "
                  "(custom content, owner-approved exception to 1.65)"}, indent=1), encoding='utf-8')


if __name__ == '__main__':
    main()
