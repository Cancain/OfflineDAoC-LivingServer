"""Find any DAoC texture by basename (loose DDS/TGA/BMP files or entries inside .npk/.mpk archives).

    from texture_index import TextureIndex
    idx = TextureIndex()                      # scans the client once (cached to assets/texture_index.json)
    img = idx.image('helm1n')                 # PIL RGBA image, or None

NIFs name textures without folders, and the client searches several places; the preference order below puts the
folder a model family normally lives in first (zone objects, then items, housing, frontiers, figures).
"""
import io, json, os, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from daoc_mpk import MpakArchive
from assets_pipeline import CLIENT, ROOT

CACHE = ROOT / 'assets' / 'texture_index.json'
EXTS = ('.dds', '.tga', '.bmp')
PREFER = ['zones/nifs', 'zones/dnifs', 'zones/textures', 'zones/terraintex', 'zones/trees', 'items', 'phousing',
          'frontiers', 'figures', 'effects', 'zones', '']


class TextureIndex:
    def __init__(self, rebuild=False):
        if CACHE.exists() and not rebuild:
            self.entries = json.loads(CACHE.read_text())
        else:
            self.entries = self.scan()
            CACHE.parent.mkdir(parents=True, exist_ok=True)
            CACHE.write_text(json.dumps(self.entries))
        self._archives = {}
        self.figures_first = False                         # build_monsters: figure skins before same-named others

    @staticmethod
    def scan():
        found = {}                                         # basename -> [[relative path, entry name or ""], ...]
        for root, _, files in os.walk(CLIENT):
            rel_root = os.path.relpath(root, CLIENT).replace('\\', '/')
            for f in files:
                low = f.lower()
                rel = f'{rel_root}/{f}' if rel_root != '.' else f
                if low.endswith(EXTS):
                    found.setdefault(low.rsplit('.', 1)[0], []).append([rel, ''])
                elif low.endswith(('.npk', '.mpk')):              # incl. character skin archives (ranked last)
                    try:
                        names = MpakArchive(os.path.join(root, f)).names()
                    except Exception:
                        continue
                    for n in names:
                        if n.endswith(EXTS):
                            found.setdefault(n.rsplit('.', 1)[0], []).append([rel, n])
        return found

    def __init_prefer(self):
        if not hasattr(self, 'first'):
            self.first = []                                # folders searched before PREFER (a city's own nifs folder)

    def locate(self, basename):
        self.__init_prefer()
        hits = self.entries.get(basename.lower())
        if not hits:
            return None

        def rank(hit):
            path = hit[0].lower()
            skin = 'skin' in path.rsplit('/', 1)[-1]          # figures/Mskins, items/pskins: character skins only
            if self.figures_first:
                skin = not path.startswith('figures/')         # a monster's own skin first, the oldest archive first
                                                               # (owner 2026-10-11: the black wolf wore a housing rug's
                                                               # wolf_black from phousing/nifs - 35 monsters did)
            for i, pre in enumerate(self.first):
                if path.startswith(pre):
                    return (skin, -len(self.first) + i, hit[1] != '', path)
            for i, pre in enumerate(PREFER):
                if path.startswith(pre):
                    return (skin, i, hit[1] != '', path)
            return (skin, len(PREFER), True, path)
        return min(hits, key=rank)

    def raw(self, basename):
        hit = self.locate(basename)
        if hit is None:
            return None
        rel, entry = hit
        if not entry:
            return (CLIENT / rel).read_bytes()
        if rel not in self._archives:
            self._archives[rel] = MpakArchive(str(CLIENT / rel))
        return self._archives[rel].read(entry)

    def image(self, basename):
        data = self.raw(basename)
        if data is None:
            return None
        img = Image.open(io.BytesIO(data))
        img.load()
        return img.convert('RGBA')


if __name__ == '__main__':
    idx = TextureIndex(rebuild='--rebuild' in sys.argv)
    print(len(idx.entries), 'texture names')
    for n in sys.argv[1:]:
        if not n.startswith('--'):
            print(n, idx.locate(n))
