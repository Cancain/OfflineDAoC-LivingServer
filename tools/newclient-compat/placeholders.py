"""Gives a copy of the new client the few interface files its chat and boxes need, as plain placeholders, when the
converted content (about 33 GB, from the 0.36c download) isn't there. Never run on a real install: it only fills
files that are missing.
  python placeholders.py <copy of source/new-client/godot>
"""
import struct
import sys
import zlib
from pathlib import Path


def png(size=512):
    row = b'\x00' + bytes([60, 50, 40, 255]) * size
    raw = zlib.compress(row * size)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + \
        chunk(b'IDAT', raw) + chunk(b'IEND', b'')


client = Path(sys.argv[1])
made = 0
for name in (Path(__file__).with_name('placeholders.txt')).read_text().split():
    path = client / name
    if path.exists():
        continue
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png() if name.endswith('.png') else b'')
    made += 1
print(f'{made} placeholder file(s) made')
