"""Uthgard bestiary (the 1.65 recreation's auto-bestiary, period-data archive, read only) -> per-monster drop tables with
the drop rates measured from players' kill logs. Owner ruling (2026-10-09): no ROG drops - period drop tables; so the
"ROG / unique object items" section is left out. Writes pipeline/data/uthgard_drops.json:
    {monster name (lower): {"zones": [...], "levels": [lo, hi], "killed": n,
                            "coins": rate % or null, "items": [[item name, rate %], ...], "item_ids": {name: uthgard id}}}
A name seen in several zones / pages keeps the page with the most kills.

    python parse_uthgard_drops.py"""
import html, json, re, sys
from pathlib import Path
from assets_pipeline import ROOT

PD = ROOT / 'external/old_project/development-source/research/period-data'
sys.path.insert(0, str(PD))
from read_archive import records                         # noqa: E402

OUT = Path(__file__).parent / 'data' / 'uthgard_drops.json'


def rows(section_html):
    """Table rows -> [[cell text, ...], with the item link id first when there is one]."""
    out = []
    for tr in re.findall(r'<tr[^>]*>(.*?)</tr>', section_html, re.S | re.I):
        cells = re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', tr, re.S | re.I)
        txt = [re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', c))).strip() for c in cells]
        link = re.search(r'item\.php\?load=(\d+)', tr)
        out.append((link.group(1) if link else None, txt))
    return out


def parse_monster(body):
    m = re.search(r'Statistics for "([^"]+)" found in ([^<]+?)\s*<', body)
    if not m:
        return None
    name, zone = m.group(1), m.group(2).strip()
    first = body.split('Statistics for "' + name + '" in every zone', 1)[0]     # this zone's tables only
    info = {'name': name, 'zones': [zone], 'levels': None, 'killed': 0, 'coins': None, 'items': [], 'item_ids': {}}
    # the head table: Name, Level from, Level to, Aggro, Total killed, ...
    head = re.search(r'Droprate</t[dh]>(.*?)</table>', first, re.S | re.I)   # (the header row isn't closed)
    if head:
        for _, t in rows(head.group(1)):
            if len(t) >= 5 and t[1].isdigit():
                info['levels'] = [int(t[1]), int(t[2]) if t[2].isdigit() else int(t[1])]
                info['killed'] = int(t[4]) if t[4].isdigit() else 0
                break
    # item sections: split on the section titles, skip ROG / unique object items
    parts = re.split(r'(Gear items|Craft items, sell loot and generic items|ROG / unique object items|Gear and craft items|Sell loot and generic items)', first)
    for i in range(1, len(parts) - 1, 2):
        title, sec = parts[i], parts[i + 1]
        if title.startswith('ROG'):
            continue
        for iid, t in rows(sec):
            if not t or t[0] in ('Name', 'Average per kill', '') or not t[-1].endswith('%'):
                continue
            try:
                rate = float(t[-1].rstrip('%'))
            except ValueError:
                continue
            nm = t[0]
            if nm.lower() == 'bag of coins':
                info['coins'] = rate
                continue
            info['items'].append([nm, rate])
            if iid:
                info['item_ids'][nm] = iid
    return info


def main():
    out = {}
    n = 0
    for src in ('raw_pages.jsonl.gz', 'raw_pages.repaired.jsonl.gz'):
        p = PD / 'archive/uthgard' / src
        if not p.exists():
            continue
        for r in records(str(p)):
            if 'monster.php' not in r.get('url', ''):
                continue
            info = parse_monster(r.get('body') or '')
            if not info:
                continue
            n += 1
            key = info['name'].lower()
            old = out.get(key)
            if old is None or info['killed'] > old['killed']:
                if old:
                    info['zones'] = sorted(set(old['zones']) | set(info['zones']))
                out[key] = info
            else:
                old['zones'] = sorted(set(old['zones']) | set(info['zones']))
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(out, indent=1), encoding='utf-8')
    with_items = sum(1 for v in out.values() if v['items'])
    print(n, 'monster pages,', len(out), 'monster names,', with_items, 'with item drops,',
          sum(1 for v in out.values() if v['coins'] is not None), 'with coins')


if __name__ == '__main__':
    main()
