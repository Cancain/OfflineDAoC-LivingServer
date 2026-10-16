"""One full-text index over the whole period-data archive, so any name / phrase is found in seconds instead of
re-reading 25 archive files every time (owner 2026-10-09: "you need a faster way than sitting in a python script
for 20 minutes looking for one name").

    python period_index.py build              # once (and after new crawls): pipeline/data/period_index.sqlite
    python period_index.py "Glasny"           # search: source, page date, url, a snippet
    python period_index.py '"Channeler" AND "Mag Mell"'
The archive itself is never modified (read with read_archive.records). SQLite FTS5, page text with HTML stripped,
one row per page: source (archive folder), url, date (capture / fetch / Last Updated where known), text."""
import html, json, re, sqlite3, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PERIOD = HERE.parent / 'external/old_project/development-source/research/period-data'
DB = HERE / 'data/period_index.sqlite'
sys.path.insert(0, str(PERIOD))


def page_text(r):
    body = r.get('body') or r.get('html') or ''
    if not isinstance(body, str):
        body = json.dumps(r)
    body = re.sub(r'(?is)<(script|style).*?</\1>', ' ', body)
    body = re.sub(r'<[^>]+>', ' ', body)
    return re.sub(r'\s+', ' ', html.unescape(body)).strip()


def page_date(r, text):
    for k in ('timestamp', 'ts', 'fetched', 'date'):
        v = r.get(k)
        if v and str(v) != 'None':
            return str(v)[:19]
    m = re.search(r'Last Updated:\s*([A-Z][a-z]{2}\s+\d+\s+[\d:]+\s+\d{4})', text)
    return m.group(1) if m else ''


def build():
    from read_archive import records
    DB.parent.mkdir(parents=True, exist_ok=True)
    tmp = DB.with_suffix('.building')
    if tmp.exists():
        tmp.unlink()
    db = sqlite3.connect(tmp)
    db.execute('create virtual table pages using fts5(source, url, date, text, tokenize="unicode61")')
    files = sorted(PERIOD.glob('archive/**/*.jsonl.gz')) + sorted(PERIOD.glob('quests/*.jsonl'))
    t0, n = time.time(), 0
    for f in files:
        source = f.parent.name if f.parent.name != 'archive' else f.stem
        it = records(str(f)) if f.suffix == '.gz' else (json.loads(l) for l in open(f, encoding='utf-8') if l.strip())
        rows = []
        try:
            for r in it:
                if not isinstance(r, dict):
                    continue
                text = page_text(r)
                if len(text) < 20:
                    continue
                rows.append((source + '/' + f.name, str(r.get('url') or r.get('id') or r.get('name') or ''),
                             page_date(r, text), text))
                if len(rows) >= 2000:
                    db.executemany('insert into pages values (?,?,?,?)', rows)
                    n += len(rows)
                    rows = []
        except Exception as e:
            print(f.name, 'stopped early:', type(e).__name__, e)
        if rows:
            db.executemany('insert into pages values (?,?,?,?)', rows)
            n += len(rows)
        db.commit()
        print(f'{f.relative_to(PERIOD)}: {n} pages so far ({time.time() - t0:.0f} s)', flush=True)
    db.execute("insert into pages(pages) values('optimize')")
    db.commit()
    db.close()
    if DB.exists():
        DB.unlink()
    tmp.rename(DB)
    print('done', n, 'pages')


def search(q, limit=25):
    db = sqlite3.connect(DB)
    for source, url, date, snip in db.execute(
            "select source, url, date, snippet(pages, 3, '[', ']', ' ... ', 24) from pages where pages match ? "
            "order by rank limit ?", (q, limit)):
        print(f'{date[:10]:10} {source[:40]:40} {url[:70]}\n    {snip}')


if __name__ == '__main__':
    if sys.argv[1:2] == ['build']:
        build()
    else:
        search(' '.join(sys.argv[1:]))
