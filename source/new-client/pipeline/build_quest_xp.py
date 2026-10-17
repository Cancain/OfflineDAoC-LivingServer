"""Quest experience, the period way (owner 2026-10-10: "period accurate quest xp rewards vs what is currently being
offered"; "check if it was a set amount or based on your characters level").

What the period data shows (Allakhazam quest pages and comments as the Internet Archive captured them, 2002-2004,
pipeline/data/period_index.sqlite): a quest's experience was based on your level. Players at different levels quote
numbers that are exact multiples of the experience for killing a monster of their own level (the xp_for_living
table, content/rules/rules.json):
    Gazsi's Nightmares   level 39: 170,700,780 = 18.7 x 9,128,384      level 41: 225,241,032 = 18.7 x 12,044,975
                         level 49: 356,515,840 = 17 x 20,971,520 (the level-45 value: the quest stops growing there)
    Twisted Evil         level 38: 148,603,664 = 18.7 x living(38)      level 39: 170,700,780 = 18.7 x living(39)
    Missing Tapestry     level 33: 12.1 x living(33)                    level 34: 12.1 x living(34)
    Poison for Ivy       level 31: 11 x living(31)                      level 33: 11 x living(33)
    Face the Twisted     level 42: 11 x living(42)                      level 44: 10 x living(44)
    Spirits of the Orchard level 36: ~16.5 x living(36)                 level 44: 15 x living(42)
    Corruptors, Botonids level 47 and 49: 55 x living(L);  Rhoiwyn's Necklace level 50: 79.2 x living(50) ...
  so  XP = N x living(min(level, cap)), x 1.1 while below the cap  (the 1.1 shows in every below-cap figure: 18.7 =
  17 x 1.1, 12.1 = 11 x 1.1, 55 = 50 x 1.1, 79.2 = 72 x 1.1; at or past the cap the plain N x living(cap)).
  Kill-task turn-ins are the same with N = 1 and the cap at about the task's level (Morvalt Streber Scalps 1,651,404 =
  living(30) at 31 and 34; Gold Lined Drinking Horn 5.2M = living(35) at 38; Dried Rowan Leaves living(44) at 48).

Each experience step here gets  xp_n  (the multiplier below the cap, 1.1 included) and  xp_cap; the engine pays
xp_n x living(level) below the cap and xp_n / 1.1 x living(cap) from it (QuestEngine.step_xp). Sources, in order:
  1. PERIOD: quests whose period figures pin N (and the cap where two levels are known) - the table below, each with
     its figures;
  2. PERIOD FIXED: a period figure that is a plain amount (no level known, or the low levels) - kept as that amount;
  3. the old server's own figure where it matches a period report or came from a walkthrough's number - unchanged;
  4. IMPROVISED by the old project ("xp": "auto" in its quest specs: a share of the level's span at the quest's
     level - not period): replaced by the period multiplier for the quest's level band (BAND, the median of the period
     figures above for quests of that level) and a cap of the quest's level + 5 (the period caps: +4 to +6).
Writes the steps in godot/content/quests/quests.json and pipeline/data/quest_xp_report.json.
    python build_quest_xp.py         (build_quests.py runs it too)"""
import json, re, sqlite3
from pathlib import Path
from assets_pipeline import ROOT

HERE = Path(__file__).resolve().parent
QUESTS = ROOT / 'godot/content/quests/quests.json'
RULES = ROOT / 'godot/content/rules/rules.json'
SPECS = ROOT / 'external/old_project/development-source/research/period-data/quests/specs'
OLD_XP = SPECS.parent / 'xp_table.json'
REPORT = HERE / 'data/quest_xp_report.json'
INDEX = HERE / 'data/period_index.sqlite'

# period multiplier (1.1 included) by the quest's level: the median of the period figures for quests of that level
BAND = [(10, 2.5), (19, 2.2), (25, 3.15), (30, 4.2), (35, 11.0), (39, 17.6), (42, 8.8), (46, 63.1), (50, 75.5)]
CAP_ABOVE = 5

# 1. period: (name, min level or None) -> {step index (or -1 = the last experience step): (xp_n, cap)}, why
PERIOD = {
    ("Gazsi's Nightmares", None): ({-1: (18.7, 45)}, '170,700,780 at 39, 225,241,032 at 41.5, 356,515,840 at 49'),
    ('Twisted Evil', None): ({-1: (18.7, 43)}, '148,603,664 at 38; 170,700,780 at 39'),
    ('Missing Tapestry', None): ({-1: (12.1, 38)}, '39,963,964 at 33; 50,351,451 at 34'),
    ('Poison for Ivy', None): ({-1: (11.0, 36)}, '22,887,018 at 31; 36,330,877 at 33'),
    ('Face the Twisted', None): ({-1: (11.0, 44)}, '152,196,473 at 42; 182,567,690 at 44'),
    ('Corruptors, Botonids, and Trade', None): ({-1: (55.0, 51)}, '1,521,964,785 at 47; 2,008,244,535 at 49'),
    ('Gem of the Dwarven King', None): ({-1: (58.3, 51)}, '1,613,282,672 at 47; ~2.1 billion at 49'),
    ("Kyllikki's Scrolls", None): ({-1: (5.5, 19)}, '159,390 at 15; 463,400 at 34 (4 x living(19))'),
    ("Lover's Circle", None): ({-1: (7.7, 21)}, '1,445,045 / 1,445,721 at 21 (7 x living(21))'),
    ("Wizard's Appeal", None): ({-1: (3.3, 25)}, '1,081,344 at 23; ~1.5 million at 25'),
    ('Spirits of the Orchard', None): ({-1: (16.5, 42)}, '~99 million at 36; 207,540,645 at 44 (15 x living(42))'),
    ("Rhoiwyn's Necklace", None): ({-1: (79.2, 51)}, '~2.9 billion at 49; 3,321,888,768 at 50'),
    ('Stoneheart', None): ({-1: (91.3, 51)}, '3,333,685,928 at 49'),
    ('Free the Rogue!', None): ({-1: (71.87, 51)}, '2,272,761,920 at 48'),
    ("Ogre's Might", None): ({-1: (55.0, 51)}, '2,306,867,200 at 50'),
    ("Catla's Downfall", None): ({-1: (79.2, 51)}, '2,891,872,130 (= 79.2 x living(49))'),
    ('Lord of Deceit', 48): ({-1: (68.55, 51)}, '2,167,865,216 for the journal at 48'),
    ('The Tree Maidens', None): ({-1: (68.55, 51)}, '2,167,865,216 (the level-48 figure)'),
    ('Last Heir', 43): ({-1: (68.2, 48)}, '1,642,934,658 at 46'),
    ('Voices of the Dead', None): ({-1: (68.2, 48)}, '1,886,000,000 at 47'),
    ('Feast of the Decadent', 43): ({-1: (62.0, 48)}, '"over 985,000,000" at 43'),
    ("Juuso's Potion", None): ({-1: (12.1, 38)}, '63,438,848 (= 12.1 x living(35))'),
    ('Reports', None): ({-1: (12.1, 40)}, '39.96 million at 33, 64 million (35), 115 million at 48 (11 x living(40))'),
    ('The Craft of Retribution', None): ({-1: (18.7, 45)}, '196 million, "half a bubble" (= 18.7 x living(40))'),
    ('The Forest Plot', None): ({-1: (13.2, 45)}, '"about 140 million"'),
    ('Legend of the Lake', 20): ({-1: (9.9, 25)}, '1,622,016 at 20'),
    ('Paranoid Guard', None): ({-1: (3.3, 20)}, '95,634 at 15'),
    ('The Heretical Hermit', None): ({-1: (2.64, 26)}, '612,000 at 22'),
    ("Nenet's Research", None): ({-1: (3.9, 15)}, '"20,000, more or less" at 10'),
    ('Spat the Wild Cat', None): ({-1: (4.4, 15)}, '31,856 at 11'),
    ('Escaped Bandits', None): ({-1: (2.9, 25)}, '"more than 600,000" at 21'),
    ("Sile's Sight", None): ({-1: (9.9, 27)}, '1,651,404 + 3,302,808 + 2,477,106 at 27 (2 + 4 + 3 x living(27))'),
    ('A War of Old', 30): ({-1: (3.3, 35)}, '"about 4 million" at 30'),
    ("Larylle's Necklace", None): ({-1: (6.77, 31)}, '1.9M + 3 x 1.6M + 3.3M at 41'),
    ('Lesser Of Two Evils', None): ({-1: (1.1, 24)}, '412,870 (= living(24))'),
    ("Secret of Nuada's Silver A", None): ({-1: (3.3, 45)}, '62,914,580 at 48 (3 x living(45))'),
    ("Secret of Nuada's Silver B", None): ({-1: (4.4, 45)}, '83,886,080 at 48 (4 x living(45))'),
    ('Seek the Moonstone B', None): ({-1: (3.3, 25)}, '681,235 (= 3.3 x living(21))'),
    ('Gold Lined Drinking Horn -- Kill Task', None): ({-1: (1.1, 35)}, '5.2 million per horn at 38'),
    ('Morvalt Streber Scalps -- Kill Task', None): ({-1: (1.1, 30)}, '1,651,404 at 31 and at 34'),
    ('Dried Rowan Leaves -- Kill Task', None): ({-1: (1.1, 44)}, '18,256,769 per leaf at 48'),
    ('Fall of an Emperor', None): ({11: (8.8, 41), 13: (8.8, 41)}, '60,878,593 at 37 for a step'),
    ('Lost Maps', None): ({-1: (7.7, 33)}, '"little over 16 million" at 32'),
    ('Failing Magic', None): ({-1: (8.8, 31)}, '5,767,168 at 26'),
    ('Immortal Gift', None): ({1: (1.1, 48)}, '"roughly 17 million" on entering Treibh Caillte at 43'),
    ('Zombies, Ghosts, and Necromancers', None): ({3: (2.2, 45), 7: (29.7, 45)}, '40,164,891 and 542,226,039 at 44'),
    ('Under Attack', None): ({-1: (4.55, 44)}, '72,269,856 for the commander at 43'),
    ('Mammoth Hunt', None): ({8: (39.6, 51), 16: (57.5, 51)}, '1,444,000,000 for the tusks, ~2.1 billion final at 49'),
    ("Crace's Desire", None): ({3: (2.86, 40), 4: (0.95, 40)}, '"around 20 mil" at 35'),
    ('Whatcha Gonna Do', None): ({-1: (2.2, 17)}, '45,056 at 14'),
}
# 2. period fixed amounts: (name, min or None) -> {step index or -1: amount}, why
FIXED = {
    ("Aegan's Letter to Helen", None): ({-1: 160}, '160 at level 3'),
    ('Track and Seek', None): ({-1: 400}, '400'),
    ('Scura Tragedia', None): ({-1: 115920}, '115,920 (4 x living(15), the quest\'s own level)'),
    ("Siom's Staff", None): ({1: 20000, -1: 40000}, '20K for the dust, 40K for the backbone'),
    ('Bandit Camp', None): ({2: 10000, -1: 7000}, '10k for the sealed note, 7k for the head'),
    ('Animare Il Morti', None): ({-1: 2600800}, '2,600,800 (5 x living(25), the quest\'s own level)'),
    ('Simple Request', None): ({-1: 1280}, '1280'),
    ('Dying Favor', None): ({-1: 1290}, '1,290'),
    ('Association', None): ({-1: 160}, '160'),
    ("Kylirean's New Armor", None): ({-1: 80}, '"You are awarded 80 experience!"'),
    ("Trapper's Pride", None): ({-1: 150}, '"150 exp i think"'),
    ("Rinda's Lost Keys", None): ({1: 20, -1: 20}, '20 for the keychain, 20 for the key'),
    ('Magical Disturbances', None): ({-1: 160}, '"You are awarded 160 experience!"'),
    ('Souls of the Dead', None): ({-1: 88}, '"You are awarded 88 experience!"'),
    ('Protecting the Groves', None): ({-1: 22}, '"You are awarded 22 experience!"'),
}


def norm(name):
    name = re.sub(r'\s*Submitted by:.*$', '', name).strip()
    name = re.sub(r'\s*--\s*Kill Task$', ' kill task', re.sub(r'\s*\((?:level \d+)\)\s*$', '', name))
    return re.sub(r'[^a-z0-9 ]', '', name.lower()).strip()


def period_reports():
    """norm(quest name) -> every experience figure on its period Allakhazam page (walkthrough + comments)."""
    num = r'(\d{1,3}(?:[,\.]\d{3})+|\d+(?:\.\d+)?)\s*(k|mil|million|m)?\s*(?:exp|xp|experience|exps)'
    out = {}
    db = sqlite3.connect(INDEX)
    for text, in db.execute("select text from pages where source='wayback-allakhazam/quest_pages.jsonl.gz'"):
        m = re.search(r'last config update: [^:]+:\d\d:\d\d \d{4} (.+?) Realm: (Albion|Midgard|Hibernia)', text)
        if not m:
            continue
        vals = out.setdefault(norm(m.group(1)), set())
        for x in re.finditer(num, text[m.end():], re.I):
            g = x.group(1)
            v = float(g.replace(',', '').replace('.', '') if re.search(r'[,\.]\d{3}', g) else g)
            u = (x.group(2) or '').lower()
            vals.add(int(v * (1000 if u == 'k' else 1e6 if u in ('m', 'mil', 'million') else 1)))
    return out


def near(a, b):
    return abs(a - b) <= max(2, (0.10 if str(a).endswith('000') else 0.03) * b)


def band(level):
    return next(n for top, n in BAND if level <= top)


def old_auto(value, level, table):
    """The old project's improvised amount (gen_dataquests.quest_xp) - to recognise it, never to use it."""
    level = max(1, min(49, int(level or 1)))
    span = table[level] - table[level - 1]
    shares = [(5, 0.16), (10, 0.15), (20, 0.084), (30, 0.026), (40, 0.015), (50, 0.056)]
    t = str(value).lower()
    if t == 'auto':
        return int(span * next(s for top, s in shares if level <= top))
    words = {'quarter': 0.25, 'half': 0.5, 'three quarters': 0.75, '3/4': 0.75, 'one': 1, 'two': 2, 'three': 3, 'four': 4}
    m = re.search(r'(\d+(?:\.\d+)?)\s*bubble', t)
    n = float(m.group(1)) if m else next((v for k, v in words.items() if k in t), 0.5 if 'small' in t else 1)
    if 'almost' in t or 'nearly' in t:
        n *= 0.9
    return int(span * n / 10)


def improvised_values():
    """(realm, name) -> amounts the old project made up for that quest (non-number "xp" in its spec)."""
    table = json.loads(OLD_XP.read_text(encoding='utf-8'))
    out = {}
    files = sorted(SPECS.glob('*.jsonl'), key=lambda p: (p.stem not in ('albion', 'midgard', 'hibernia'), p.name))
    for f in files:
        for line in f.read_text(encoding='utf-8').splitlines():
            try:
                s = json.loads(line)
            except ValueError:
                continue
            key = (s.get('realm', ''), s.get('name', ''))
            if key in out:
                continue
            vals = set()

            def walk(o):
                if isinstance(o, dict):
                    for k, v in o.items():
                        if k == 'xp' and v not in (None, '') and not isinstance(v, (int, float)):
                            vals.add(old_auto(v, s.get('level', 1), table))
                        walk(v)
                elif isinstance(o, list):
                    for v in o:
                        walk(v)
            walk(s)
            out[key] = vals
    return out


def realm_of(q):
    r = int(q.get('giver_region', 0))
    return 'Midgard' if 100 <= r < 200 else 'Hibernia' if 200 <= r < 300 else 'Albion'


def lookup(table, q):
    base = re.sub(r'\s*\(level \d+\)\s*$', '', q['name']).strip()
    return table.get((base, int(q['min']))) or table.get((base, None))


def apply(out):
    """Set every experience step's period values in a quests.json dict; returns the report."""
    impro = improvised_values()
    table = json.loads(OLD_XP.read_text(encoding='utf-8'))
    auto = {old_auto('auto', lv, table) for lv in range(1, 50)}      # the old project's level amounts
    reports = period_reports()
    rep = {'period': {}, 'period_fixed': {}, 'improvised_replaced': {}, 'kept': 0}
    for qid, q in out['quests'].items():
        steps = q.get('steps', [])
        xp_steps = [i for i, s in enumerate(steps) if int(s.get('xp', 0)) > 0 or 'xp_n' in s]
        last = xp_steps[-1] if xp_steps else len(steps) - 1
        for s in steps:                                   # a clean slate each run
            s.pop('xp_n', None)
            s.pop('xp_cap', None)
            if 'xp_old' in s:
                s['xp'] = s.pop('xp_old')
        p, f = lookup(PERIOD, q), lookup(FIXED, q)
        if p:
            for i, (n, cap) in p[0].items():
                i = last if i == -1 else i
                if 0 <= i < len(steps):
                    steps[i].update(xp_n=n, xp_cap=cap)
            rep['period'][qid] = {'name': q['name'], 'figures': p[1]}
            continue
        if f:
            for i, amount in f[0].items():
                i = last if i == -1 else i
                if 0 <= i < len(steps):
                    steps[i]['xp_old'] = steps[i]['xp']
                    steps[i]['xp'] = amount
            rep['period_fixed'][qid] = {'name': q['name'], 'figures': f[1]}
            continue
        made_up = impro.get((realm_of(q), q['name']), set()) | auto
        said = reports.get(norm(q['name']), set())
        lv = int(q['min'])
        kill_task = 'kill task' in q['name'].lower()
        changed = []
        for i in xp_steps:
            v = int(steps[i]['xp'])
            if v in made_up and not any(near(r, v) for r in said):   # a period figure backs it: kept
                n, cap = (1.1, max(1, lv - 1)) if kill_task else (band(lv), min(51, lv + CAP_ABOVE))
                steps[i].update(xp_n=n, xp_cap=cap)
                changed.append((i, v, n, cap))
        if changed:
            rep['improvised_replaced'][qid] = {'name': q['name'], 'min': lv, 'steps': changed}
        else:
            rep['kept'] += 1
    return rep


def main():
    out = json.loads(QUESTS.read_text(encoding='utf-8'))
    rep = apply(out)
    QUESTS.write_text(json.dumps(out, indent=1), encoding='utf-8')
    REPORT.write_text(json.dumps(rep, indent=1), encoding='utf-8')
    print('quests', len(out['quests']), 'period', len(rep['period']), 'period fixed', len(rep['period_fixed']),
          'improvised replaced', len(rep['improvised_replaced']), 'kept', rep['kept'])


if __name__ == '__main__':
    main()
