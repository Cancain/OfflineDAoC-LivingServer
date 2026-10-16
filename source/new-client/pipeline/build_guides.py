"""QUEST GUIDE text from the period Allakhazam walkthroughs (owner 2026-10-09: the guide button must open the quest's
Allakhazam guide, as the old OfflineDAoC did). The old project's classic-quest-guides.json covers ~450 quests; for
the rest it only had a stand-in ("No Allakhazam walkthrough was found; these are the quest's journal steps"). The
period-data archive (read only) holds 590 Allakhazam walkthrough pages (quests/walkthroughs.jsonl, "Last Updated"
2002-2004): a quest without a real guide gets its walkthrough, matched by name - "(version N)" pages choose the
version whose Start NPC / Related NPCs / Start Zone / Class fit the quest (its giver, step targets, zone, classes).
Merges into godot/content/quests/quests.json "guides".

    python build_guides.py"""
import json, re
from assets_pipeline import ROOT
from build_zone import zone_name

PD = ROOT / 'external/old_project/development-source/research/period-data'
QUESTS = ROOT / 'godot/content/quests/quests.json'
STAND_IN = 'No Allakhazam walkthrough was found'
CLASS_NAMES = {}                                          # class id -> name (godot/content classes)


def class_names():
    p = ROOT / 'godot/content/classes/classes.json'
    if p.exists():
        d = json.loads(p.read_text(encoding='utf-8'))
        for k, v in (d.get('classes', d)).items():
            if isinstance(v, dict) and v.get('name'):
                CLASS_NAMES[int(k)] = str(v['name']).lower()


def head_field(head, key):
    return head[head.index(key) + 1].strip() if key in head and head.index(key) + 1 < len(head) else ''


def related(head):
    if 'Related NPCs:' not in head:
        return []
    out = []
    for x in head[head.index('Related NPCs:') + 1:]:
        if x.endswith(':'):
            break
        out.append(x.strip().lower())
    return out


def main():
    class_names()
    d = json.loads(QUESTS.read_text(encoding='utf-8'))
    pages = {}
    for line in (PD / 'quests/walkthroughs.jsonl').read_text(encoding='utf-8').splitlines():
        w = json.loads(line)
        if int(w.get('status', 200)) != 200 or not w.get('body'):
            continue
        base = re.sub(r'\s*\(version \d+\)\s*$', '', w['title'].strip(), flags=re.I).lower()
        pages.setdefault(base, []).append(w)
    added, kept, missing = 0, 0, []
    for q in d['quests'].values():
        name = q['name']
        g = d['guides'].get(name)
        if g and STAND_IN not in str(g.get('source', '')):
            kept += 1
            continue
        cands = pages.get(name.strip().lower(), [])
        if not cands:
            if not g:
                missing.append(name)
            continue
        npcs = {str(q.get('giver', '')).lower()} | {str(s.get('target', '')).lower() for s in q.get('steps', [])}
        zname = zone_name(int(q['zone'])).lower() if q.get('zone') is not None else ''
        classes = {CLASS_NAMES.get(int(c), '') for c in q.get('classes', [])}

        def score(w):
            h = w.get('head', [])
            s = 0
            s += 3 * len(npcs & set(related(h) + [head_field(h, 'Start NPC:').lower()]))
            s += 2 if zname and head_field(h, 'Start Zone:').lower() == zname else 0
            s += 2 if head_field(h, 'Class:').lower() in classes else 0
            return s
        w = max(cands, key=score)
        h = w.get('head', [])
        d['guides'][name] = {'source': 'Allakhazam walkthrough: %s (camelot.allakhazam.com, period-data archive)' % w['title'],
                             'updated': head_field(h, 'Last Updated:') or None, 'lines': list(w['body'])}
        added += 1
    QUESTS.write_text(json.dumps(d, indent=1), encoding='utf-8')
    print(f'{added} quests got a period walkthrough, {kept} kept their old guide, {len(missing)} have none: {sorted(set(missing))[:20]}')


if __name__ == '__main__':
    main()
