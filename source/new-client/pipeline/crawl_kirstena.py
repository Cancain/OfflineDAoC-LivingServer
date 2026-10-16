"""Slow, polite crawl of Kirstena's Atlas (2001-2003 hand-made zone / dungeon maps: monster areas with level ranges
"according to Illia's Bestiary", named monsters, stables, bindstones, guard towers, merchants) from the mirror at
https://www.moose.at/kirstena/ (owner 2026-10-10: "very slowly grab those zone maps ... save them in period data").
One file at a time, 60-120 s apart; files already saved are skipped, so it can be stopped and run again.
    python crawl_kirstena.py        -> period data/kirstena maps/<albionmaps|hibmaps|midmaps>/..., index.html, crawl_log.txt"""
import random, re, time, urllib.request
from pathlib import Path
from urllib.parse import urljoin

BASE = 'https://www.moose.at/kirstena/'
OUT = Path(__file__).resolve().parent.parent / 'period data' / 'kirstena maps'
UA = {'User-Agent': 'Mozilla/5.0 (personal offline archive; one request a minute)'}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    log = (OUT / 'crawl_log.txt').open('a', encoding='utf-8')
    page = get(BASE)
    (OUT / 'index.html').write_bytes(page)
    links = sorted({urljoin(BASE, m) for m in re.findall(rb'(?:href|src)="([^"#?]+\.(?:gif|jpe?g|pdf|png))"', page, re.I)
                    for m in [m.decode('latin1')] if urljoin(BASE, m).startswith(BASE)})
    log.write(f'{time.ctime()} index: {len(links)} files\n'); log.flush()
    for i, url in enumerate(links):
        dest = OUT / url[len(BASE):]
        if dest.exists() and dest.stat().st_size > 0:
            continue
        time.sleep(random.uniform(60, 120))
        try:
            data = get(url)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            log.write(f'{time.ctime()} {i + 1}/{len(links)} {url} {len(data)} bytes\n')
        except Exception as e:
            log.write(f'{time.ctime()} {i + 1}/{len(links)} {url} FAILED {type(e).__name__} {e}\n')
        log.flush()
    log.write(f'{time.ctime()} done\n')


if __name__ == '__main__':
    main()
