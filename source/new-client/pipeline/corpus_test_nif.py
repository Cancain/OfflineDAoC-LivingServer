"""Parse every NIF in the DAoC client with netimmerse.py and report failures (MMOEngine pipeline check)."""
import collections, os, sys, time, traceback
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from daoc_mpk import read_mpk
from assets_pipeline import CLIENT
from netimmerse import read_nif

def nifs():
    for root, _, files in os.walk(CLIENT):
        for f in files:
            p = os.path.join(root, f); low = f.lower()
            if low.endswith('.nif'):
                yield p, open(p, 'rb').read()
            elif low.endswith(('.npk', '.mpk')):
                try:
                    items = read_mpk(p).items()
                except Exception:
                    continue
                for n, raw in items:
                    if n.endswith('.nif'):
                        yield f'{p}:{n}', raw

def main():
    only_old = '--all' not in sys.argv
    ok, fails, trailing = collections.Counter(), collections.Counter(), collections.Counter()
    examples = {}
    t0 = time.time()
    for path, raw in nifs():
        head = raw[:raw.find(b'\n')].decode('latin1', 'replace')
        if not head.startswith(('NetImmerse', 'Gamebryo')):
            continue
        v = head.split('Version ')[-1]
        if only_old and v.startswith('10.'):
            continue
        try:
            nif = read_nif(raw)
            if nif.trailing:
                trailing[v] += 1; examples.setdefault(('trailing', v), path)
            else:
                ok[v] += 1
        except Exception as e:
            tb = traceback.extract_tb(e.__traceback__)
            key = (v, type(e).__name__, str(e)[:90])
            fails[key] += 1; examples.setdefault(key, path)
    print(f'{time.time() - t0:.0f}s ok', dict(ok), 'trailing', dict(trailing))
    for k, c in fails.most_common(40):
        print(c, k, '\n     e.g.', examples[k])
    for k, pth in examples.items():
        if k[0] == 'trailing': print('trailing e.g.', k, pth)

if __name__ == '__main__':
    main()
