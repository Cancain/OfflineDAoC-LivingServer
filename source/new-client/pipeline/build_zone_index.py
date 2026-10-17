"""Every zone's place in its region (the client's zones.dat): content/zones/zones_index.json
  {zone id: {name, region, x, y (region offset, 8192-unit cells), w, h (cells), type, built}}
The engine uses it to walk across zone borders inside a region (the outdoor zones of a realm sit side by side in one
region, as the client draws them): leaving a zone's edge loads the neighbour at the same region spot."""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import CLIENT, ROOT
from daoc_mpk import read_mpk


def main():
    text = read_mpk(str(CLIENT / 'zones/zones.mpk'))['zones.dat'].decode('latin1')
    out = {}
    for m in re.finditer(r'\[zone(\d{3})\](.*?)(?=\n\[|\Z)', text, re.S | re.I):
        zid, body = int(m.group(1)), m.group(2)
        kv = {}
        for line in body.splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                kv[k.strip().lower()] = v.strip()
        if 'region' not in kv:
            continue
        num = lambda k, d=0: int(re.match(r'-?\d+', kv.get(k, str(d))).group(0)) if re.match(r'-?\d+', kv.get(k, str(d))) else d
        out[str(zid)] = {'name': kv.get('name', f'zone{zid:03d}'), 'region': num('region'),
                         'x': num('region_offset_x'), 'y': num('region_offset_y'), 'w': num('width', 8), 'h': num('height', 8),
                         'type': num('type'), 'built': (ROOT / f'godot/content/zones/zone{zid:03d}/zone.json').exists()}
    f = ROOT / 'godot/content/zones/zones_index.json'
    f.write_text(json.dumps(out, indent=1), encoding='utf-8')
    hib = {k: v for k, v in out.items() if v['region'] == 200}
    print(len(out), 'zones;', 'region 200:', {k: (v['name'], v['x'], v['y'], v['w'], v['h'], v['built']) for k, v in hib.items()})


if __name__ == '__main__':
    main()
