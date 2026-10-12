"""Check the bot-voice line files and build corpus.json.

  python tools/bot-voices/build_corpus.py            (check and write corpus.json, print coverage)
  python tools/bot-voices/build_corpus.py --check    (check only; exit 1 on any problem)

Line files: source/server/GameServer/bots/autonomous/data/chat/*.lines. The format is described in
docs/bot-voices/DESIGN.md (section 3). Every line is new writing for this project.
"""
import argparse
import collections
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHAT = ROOT / 'source/server/GameServer/bots/autonomous/data/chat'
OUT = CHAT / 'corpus.json'

KINDS = {'ambient', 'reply', 'lfg', 'trade', 'rvr', 'greet', 'thanks', 'grudge', 'gossip', 'ding', 'death',
         'camp', 'debate'}
TYPES = {'Leveler', 'Crafter', 'Socialite', 'Explorer', 'Daredevil', 'NoLifer'}
REALMS = {'alb', 'mid', 'hib'}
CLASSES = {
    'alb': {'Armsman', 'Paladin', 'Mercenary', 'Reaver', 'Scout', 'Infiltrator', 'Minstrel', 'Cleric', 'Friar',
            'Wizard', 'Theurgist', 'Sorcerer', 'Cabalist', 'Necromancer'},
    'mid': {'Warrior', 'Thane', 'Skald', 'Berserker', 'Savage', 'Hunter', 'Shadowblade', 'Healer', 'Shaman',
            'Runemaster', 'Spiritmaster', 'Bonedancer'},
    'hib': {'Hero', 'Champion', 'Blademaster', 'Warden', 'Druid', 'Bard', 'Ranger', 'Nightshade', 'Eldritch',
            'Enchanter', 'Mentalist', 'Animist', 'Valewalker'},
}
ALL_CLASSES = set().union(*CLASSES.values())
FLAGS = {'in_group', 'solo', 'in_town', 'in_dungeon', 'in_rvr', 'at_camp', 'traveling', 'just_leveled',
         'just_died', 'bag_full', 'has_listing', 'knows_player', 'player_nearby'}
INTENTS = {'unknown', 'greeting', 'banter', 'abuse', 'grouping', 'grinding', 'travel', 'dungeon', 'rvr',
           'trading', 'help', 'farewell', 'ignoreoutofworld'}
MOODS = {'friendly', 'neutral', 'cool', 'rival'}
SLOTS = {'me', 'class', 'level', 'realm', 'zone', 'monster', 'npc', 'item', 'count', 'camp', 'dungeon',
         'capital', 'enemy', 'keep', 'frontier', 'player', 'player_class', 'place', 'q'}
MEMORY_SLOTS = {'player', 'player_class', 'place'}
MAX_RAW = 140

# Out of era (Trials of Atlantis, New Frontiers, Catacombs), the custom class, real-world names, profanity.
BANNED = [
    r'atlantis', r'\btoa\b', r'artifact', r'master ?levels?', r'\bml\d*\b', r'champion levels?', r'\bcl\d*\b',
    r'catacombs', r'labyrinth', r'new frontiers?', r'\btowers?\b', r'oceanus', r'stygia', r'aerus', r'volcanus',
    r'mauler', r'vampiir', r'bainshee', r'heretic', r'valkyr', r'warlock', r'frostalf', r'\bshar\b', r'deifrang',
    r'minotaur', r'sluagh', r'mythic', r'\bign\b', r'\bvault\b', r'allakhazam', r'everquest', r'world of warcraft',
    r'\bfuck', r'\bshit', r'\bbitch', r'\bdamn', r'\bass\b', r'\bcrap\b', r'\bhell\b',
]
BANNED_RE = re.compile('|'.join(BANNED), re.IGNORECASE)
SLOT_RE = re.compile(r'\{([^{}]*)\}')


class Problem(Exception):
    pass


def parse_levels(value, where):
    if value == '*':
        return [1, 50]
    m = re.fullmatch(r'(\d+)-(\d+)', value)
    if not m or not 1 <= int(m.group(1)) <= int(m.group(2)) <= 50:
        raise Problem(f'{where}: bad @levels "{value}"')
    return [int(m.group(1)), int(m.group(2))]


def split_list(value):
    return [] if value in ('', '*') else [v.strip() for v in value.split(',') if v.strip()]


def check_text(text, tags, where, problems):
    if len(text) > MAX_RAW:
        problems.append(f'{where}: {len(text)} characters (max {MAX_RAW}): {text}')
    for slot in SLOT_RE.findall(text):
        if slot not in SLOTS:
            problems.append(f'{where}: unknown slot {{{slot}}}')
        elif slot in MEMORY_SLOTS and 'knows_player' not in tags['needs'] and tags['kind'] not in (
                'greet', 'thanks', 'grudge', 'gossip'):
            problems.append(f'{where}: memory slot {{{slot}}} needs @needs knows_player or a memory kind')
    if text.count('{') != text.count('}'):
        problems.append(f'{where}: unbalanced braces')
    hit = BANNED_RE.search(SLOT_RE.sub('', text))
    if hit:
        problems.append(f'{where}: out-of-era or banned word "{hit.group(0)}": {text}')


def check_tags(tags, where, problems):
    if tags['kind'] not in KINDS:
        problems.append(f'{where}: unknown @kind {tags["kind"]}')
    for t in tags['who']:
        if t not in TYPES:
            problems.append(f'{where}: unknown type {t}')
    if tags['realm'] not in REALMS | {'*'}:
        problems.append(f'{where}: unknown @realm {tags["realm"]}')
    allowed = CLASSES.get(tags['realm'], ALL_CLASSES)
    for c in tags['class']:
        if c not in allowed:
            problems.append(f'{where}: class {c} is not in realm {tags["realm"]}')
    for f in tags['needs']:
        if f not in FLAGS:
            problems.append(f'{where}: unknown flag {f}')
    if tags['intent'] and tags['intent'] not in INTENTS:
        problems.append(f'{where}: unknown @intent {tags["intent"]}')
    if tags['kind'] == 'reply' and not tags['intent']:
        problems.append(f'{where}: reply lines need @intent')
    if tags['mood'] and tags['mood'] not in MOODS:
        problems.append(f'{where}: unknown @mood {tags["mood"]}')


def fresh_tags():
    return dict(kind='ambient', topic='general', who=[], realm='*', **{'class': []}, levels=[1, 50], needs=[],
                intent='', mood='', weight=1.0)


def parse_file(path, problems):
    lines, scenes = [], []
    tags = fresh_tags()
    scene = None
    for number, raw in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        where = f'{path.name}:{number}'
        text = raw.strip()
        if not text or text.startswith('#'):
            continue
        if text.startswith('@'):
            key, _, value = text[1:].partition(' ')
            value = value.split(' #', 1)[0].strip()
            if key == 'scene':
                scene = dict(id=value, topic=tags['topic'], realm=tags['realm'], levels=tags['levels'], roles={},
                             beats=[], where=where)
                scenes.append(scene)
            elif key == 'role':
                if scene is None:
                    problems.append(f'{where}: @role outside a scene')
                    continue
                role, _, spec = value.partition(' ')
                req = dict(p.split('=', 1) for p in spec.split() if '=' in p)
                for t in split_list(req.get('type', '')):
                    if t not in TYPES:
                        problems.append(f'{where}: unknown type {t}')
                for c in split_list(req.get('class', '')):
                    if c not in ALL_CLASSES:
                        problems.append(f'{where}: unknown class {c}')
                scene['roles'][role] = dict(type=split_list(req.get('type', '')), **{'class': split_list(req.get('class', ''))})
            elif key == 'end':
                scene = None
            else:
                scene = None
                try:
                    if key == 'kind':
                        tags = fresh_tags() | dict(kind=value)
                    elif key == 'topic':
                        tags['topic'] = value
                    elif key == 'who':
                        tags['who'] = split_list(value)
                    elif key == 'realm':
                        tags['realm'] = value
                    elif key == 'class':
                        tags['class'] = split_list(value)
                    elif key == 'levels':
                        tags['levels'] = parse_levels(value, where)
                    elif key == 'needs':
                        tags['needs'] = split_list(value)
                    elif key == 'intent':
                        tags['intent'] = value.lower()
                    elif key == 'mood':
                        tags['mood'] = value
                    elif key == 'weight':
                        tags['weight'] = float(value)
                    else:
                        problems.append(f'{where}: unknown directive @{key}')
                except Problem as error:
                    problems.append(str(error))
            continue
        if scene is not None:
            pause = re.fullmatch(r'~\s*(\d+)', text)
            if pause:
                seconds = int(pause.group(1))
                if not 5 <= seconds <= 600:
                    problems.append(f'{where}: a pause must be 5-600 seconds')
                scene['beats'].append(dict(role='~', pause=seconds))
                continue
            m = re.fullmatch(r'([A-Z]):\s*(.+)', text)
            if not m:
                problems.append(f'{where}: scene beats look like "A: text"')
                continue
            role, beat = m.groups()
            check_text(beat, dict(kind='debate', needs=[]), where, problems)
            scene['beats'].append(dict(role=role, text=beat))
            continue
        check_tags(tags, where, problems)
        check_text(text, tags, where, problems)
        lines.append(dict(tags, text=text, where=where, **{'class': list(tags['class'])}))
    for s in scenes:
        roles_used = {b['role'] for b in s['beats'] if b['role'] != '~'}
        if sum(1 for b in s['beats'] if b['role'] != '~') < 3:
            problems.append(f'{s["where"]}: scene {s["id"]} needs at least 3 beats')
        if len(roles_used) < 2:
            problems.append(f'{s["where"]}: scene {s["id"]} needs at least 2 speakers')
        for r in s['roles']:
            if r not in roles_used:
                problems.append(f'{s["where"]}: scene {s["id"]} declares role {r} that never speaks')
    return lines, scenes


def norm(text):
    return re.sub(r'[^a-z0-9{}]+', ' ', text.lower()).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    problems, lines, scenes = [], [], []
    files = sorted(CHAT.glob('*.lines'))
    if not files:
        raise SystemExit('No .lines files found in ' + str(CHAT))
    for path in files:
        l, s = parse_file(path, problems)
        lines += l
        scenes += s
    seen = {}
    for line in lines:
        key = (line['kind'], norm(line['text']))
        if key in seen:
            problems.append(f'{line["where"]}: duplicate of {seen[key]}: {line["text"]}')
        seen.setdefault(key, line['where'])
    scene_ids = collections.Counter(s['id'] for s in scenes)
    problems += [f'duplicate scene id {k}' for k, n in scene_ids.items() if n > 1]

    # Coverage minimums: every realm and level band needs ambient and lfg material it can use.
    def usable(kind, realm, lo, hi):
        return sum(1 for x in lines if x['kind'] == kind and x['realm'] in ('*', realm)
                   and x['levels'][0] <= hi and x['levels'][1] >= lo)
    bands = [(1, 19), (20, 34), (35, 50)]
    minimum = {'ambient': 60, 'lfg': 15, 'reply': 40, 'greet': 10, 'thanks': 10}
    for realm in sorted(REALMS):
        for lo, hi in bands:
            for kind, need in minimum.items():
                have = usable(kind, realm, lo, hi)
                if have < need:
                    problems.append(f'coverage: {kind} for {realm} {lo}-{hi} has {have}, needs {need}')

    if problems:
        print(f'{len(problems)} problem(s):')
        for p in problems:
            print('  ' + p)
        raise SystemExit(1)

    by_kind = collections.Counter(x['kind'] for x in lines)
    spoken = [sum(1 for b in s['beats'] if b['role'] != '~') for s in scenes]
    print(f'{len(lines)} lines, {len(scenes)} debate scenes, {sum(spoken)} scene lines '
          f'(longest {max(spoken)}, {sum(1 for n in spoken if n >= 20)} scenes of 20+ lines)')
    print('by kind: ' + ', '.join(f'{k} {n}' for k, n in sorted(by_kind.items())))
    print('by realm: ' + ', '.join(f'{k} {n}' for k, n in sorted(collections.Counter(x["realm"] for x in lines).items())))
    print('by type (lines that name types): ' + ', '.join(
        f'{t} {sum(1 for x in lines if t in x["who"])}' for t in sorted(TYPES)))
    if args.check:
        return
    out = dict(version=1, note='New lines written for Offline DAoC; see docs/bot-voices. Built by tools/bot-voices/build_corpus.py.',
               lines=[{k: v for k, v in dict(x, id=hashlib.sha1((x['kind'] + '|' + x['text']).encode()).hexdigest()[:12]).items()
                       if k != 'where'} for x in lines],
               scenes=[{k: v for k, v in s.items() if k != 'where'} for s in scenes])
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print('wrote', OUT.relative_to(ROOT))


if __name__ == '__main__':
    main()
