"""Period fixes for the client's map pictures (owner 2026-10-09: "comb over all the maps and flag and fix any high
likelihood period inaccurate details"). The client is a much later one than 1.65; its maps show things that weren't
in the game then. Each edit is painted out (OpenCV Telea inpainting from the surrounding picture) on the 256-px
client picture before the 4x upscale; the untouched pictures stay in content/maps/client/.

  BOATS     boat taxis and their light-blue routes (Lough Derg, Silvermine, Camelot Hills, East Svealand, Gotar):
            no sailing in 1.65 (owner: boats came with Trials of Atlantis). The boat sprite is found by template match
            (the same sprite on every map; 12 on 5 maps, none elsewhere), the routes by their light-blue colour.
  EXTENSIONS the classic dungeons' Catacombs-era instanced extensions - the red names with a red entrance tick
            (Deliah's Sanctuary, Lost Wing, Hidden Crypt, Hall of Reawakening, Betrayer's Den, Ritual Hall, Lair of
            Doom, The Arena, Goblin's Cookery, Beastmaster Den, Master's Lair, Arachnid Labyrinth, Lost Burrow, Den of
            Bones, The Burrow, Cursed Lair, Liche's Unrest, Lios' Eternal Rest, Tomte Prison, Nisse's Retreat,
            Forgotten Vein, Pit of Despair, Serf's Folly, Steward's Crypt, Rise of the Spraggons, The Warrens,
            Brawler's Den, Fetena's Sorrow, Ancient's Retreat, Shaman's Inner Sanctum).
  ABANDONED MINES the dungeons' exits into the Catacombs' Abandoned Mines (Catacombs, 2005): the label (found by
            template match of the word) and its yellow exit tick.
  CATACOMBS the capital cities' "Catacombs" entrance labels (Camelot, Jordheim, Tir na Nog) and their ticks.
  DOMES     the small dome icons with no dungeon behind them in the 1.65 world (30 on 14 maps).
  SI LABELS the Shrouded Isles portal labels moved back to their 1.65 places (Connla, Avalon Marsh, Nalliten).
  TOWERS    guard tower icons for the New Frontiers towers the later client added (owner 2026-10-10 "remove these two
            missing towers"): Camelot Hills' Cotswold tower (13916, 26591) and the tower the later client moved to
            19342, 30990 - that icon goes to the 1.65 tower's place (fixture 36, 19456, 26368), which the later map
            doesn't mark. An icon's bottom centre is its spot (the 1.65 tower at 39936, 32000 checks it).
Removed pixels are filled with a patch of the same picture from nearby (the one whose edge matches best, holding no
text or icon) - inpainting smeared the Prydwen Keep icon and label (owner 2026-10-10); Telea only where no clean
patch is found.
"""
from pathlib import Path
import numpy as np
import cv2
from PIL import Image

BOAT_MAPS = {'z000', 'z101', 'z103', 'z200', 'z201'}
# maps whose light-blue boat line is the river's own centre line (Camelot Hills: removing it smeared the river,
# the Prydwen Keep windows and label, owner 2026-10-10): only the boat sprites go
ROUTE_IS_RIVER = {'z000'}
# guard tower icons of post-1.65 towers (x0, y0, x1, y1), and icons moved to their 1.65 place: (box, to x0, y0)
TOWERS = {'z000': [(51, 92, 58, 105), (72, 108, 79, 122)]}
ICON_MOVES = {'z000': [((72, 108, 79, 122), (72, 90))]}
# classic dungeons whose maps carry the red extension names (Darkness Falls / Hall of the Corrupt / the epic
# dungeons use red for realm areas and keys, and are left alone)
EXTENSION_MAPS = {'z019', 'z019_00', 'z019_01', 'z021', 'z022', 'z023', 'z024', 'z125', 'z125_00', 'z125_01', 'z126',
                  'z127', 'z128', 'z129', 'z220', 'z221', 'z222', 'z223', 'z224'}
# label + tick boxes (x0, y0, x1, y1 in the 256-px picture) found with the scratch annotation tool
CATACOMBS_BOXES = {'z026': [(209, 136, 256, 150), (236, 125, 246, 141)],
                   'z120': [(32, 6, 82, 20), (80, 10, 94, 20)],
                   'z209': [(138, 119, 188, 145)]}


def _boat_template(src):
    g = np.asarray(Image.open(src / 'z200.png').convert('L')).astype(np.float32)
    t = g[43:54, 112:126].copy()
    return t, ((t > 170) | (t < 45)).astype(np.float32)


def _abandoned_template(src):
    g = np.asarray(Image.open(src / 'z021.png').convert('L')).astype(np.float32)
    t = g[121:131, 164:210].copy()                     # the word "Abandoned" (white, black outline)
    return t, ((t > 170) | (t < 45)).astype(np.float32)


def _matches(gray, tpl, mask, limit, gap):
    res = cv2.matchTemplate(gray, tpl, cv2.TM_SQDIFF, mask=mask) / mask.sum()
    out = []
    while True:
        mn, _, loc, _ = cv2.minMaxLoc(res)
        if mn > limit:
            return out
        out.append(loc)
        x, y = loc
        res[max(0, y - gap[1]):y + gap[1] + 1, max(0, x - gap[0]):x + gap[0] + 1] = 1e9


# the small dome icons with no dungeon behind them in the 1.65 world (owner 2026-10-10): 30 domes on 14 maps, every
# one far from any real entrance in its zone (zone exits) and from the realms' 1.65 dungeons - the client's later
# instanced dungeon entrances. (Real dungeons keep their icons: Spraggon Den, Mithra, DF, Tuscaran Glacier...)
DOMES = {'z000': [(164, 31), (49, 119), (97, 214), (49, 128)], 'z002': [(157, 175), (194, 151), (236, 41)],
         'z003': [(184, 118)], 'z008': [(176, 117), (99, 17)], 'z009': [(194, 61)],
         'z100': [(213, 95), (16, 13), (175, 220)], 'z101': [(18, 143), (105, 29), (166, 17), (238, 82)],
         'z102': [(240, 24)], 'z103': [(158, 178)], 'z105': [(242, 164)], 'z200': [(114, 3), (36, 203), (134, 8)],
         'z201': [(54, 148), (37, 129)], 'z206': [(113, 19)], 'z207': [(93, 159), (232, 209), (229, 16)]}
# the Shrouded Isles portal labels (pink icon + name) sit where the later client moved the portals - Mag Mell,
# Cotswold, Mularn. In 1.65 they were at Connla (Shannon Estuary), Avalon Marsh and Nalliten (Gotar): period
# walkthrough "the tower next to the portal to Hy Brasil" near Connla; Allakhazam "Original SI portal has been moved
# to just outside Cotswold Village" / "...outside Mularn Village" (NPCs in Avalon Marsh / Gotar, Nalliten) - and our
# world's own portal exits are there (HyBrasilEnt, AvalonExp, AegirEntr). Moved: {source: (label box, to map, to x/y)}
SI_LABELS = {'z200': ((110, 26, 159, 39), 'z202', (93, 111)),
             'z000': ((57, 94, 98, 106), 'z009', (150, 46)),
             'z100': ((201, 201, 233, 222), 'z103', (182, 100))}


OUTDOOR_FILL = {"z000"}   # only Camelot Hills (owner 2026-10-10: "leave the other maps alone" - they keep the Telea fill)


def _dome_template(src):
    g = np.asarray(Image.open(src / 'z200.png').convert('L')).astype(np.float32)
    t = g[3:10, 114:123].copy()
    return t, ((t > 150) | (t < 50)).astype(np.uint8)


def _label_mask(rgb, box):
    """The SI label's own pixels (lavender text, pink icon) and their dark outline, inside its box."""
    x0, y0, x1, y1 = box
    a = rgb[y0:y1, x0:x1].astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    ink = ((r > 130) & (b > 130) & (r - g > 12) & (b - g > 12)).astype(np.uint8)
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    return ink | (cv2.dilate(ink, np.ones((3, 3), np.uint8)) & (lum < 85).astype(np.uint8))


# "Abandoned Mines" labels the word match misses (a dimmer copy of the font): the label's box
ABANDONED_BOXES = {'z125': [(75, 81, 128, 102)], 'z125_00': [(75, 81, 128, 102)]}
K3, K5, K7 = (np.ones((n, n), np.uint8) for n in (3, 5, 7))


def _reconstruct(seed, allowed):
    """Grow seed through allowed pixels (morphological reconstruction): thin leader lines joined to a label."""
    cur = seed & allowed
    while True:
        nxt = cv2.dilate(cur, K5) & allowed                     # (5x5: steps over a line's anti-aliased gaps)
        if (nxt == cur).all():
            return cur
        cur = nxt


def _with_outline(text, lum):
    """A label's own pixels and 3 pixels round them (the letters' dark outline and soft edge)."""
    return cv2.dilate(text, K7)


DEBUG = False


def _patch_fill(a, mask, lum):
    """Fill each removed piece with a same-shaped patch of the picture from nearby: the offset (up to 40 px) whose
    pixels round the piece match best, taken from where nothing was removed and no text / icon (grey-black outline or
    white) is - the river's dark-blue banks are fine. Telea inpainting where no clean patch exists."""
    out = a.copy()
    h, w = mask.shape
    sat = a.max(axis=2).astype(int) - a.min(axis=2)
    ink = ((lum < 22) & (sat < 30)) | ((lum > 190) & (sat < 45))     # black outlines, white text (not river blue / shade)
    busy = cv2.dilate(ink.astype(np.uint8), K3) | cv2.dilate(mask, K5)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(cv2.dilate(mask, K3))
    left = np.zeros_like(mask)
    for k in range(1, n):
        x, y, bw, bh, _ = stats[k]
        piece = ((lab == k) & (mask > 0)).astype(np.uint8)
        grown = cv2.dilate(piece, K5)
        ring = (grown & (1 - cv2.dilate(mask, K3))).astype(bool)
        ys, xs = np.nonzero(grown)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        g = grown[y0:y1, x0:x1].astype(bool)
        p = piece[y0:y1, x0:x1].astype(bool)
        r = ring[y0:y1, x0:x1]
        target = a[y0:y1, x0:x1].astype(np.float32)
        best = None
        reach = 40 if (x1 - x0) * (y1 - y0) < 400 else 100           # big pieces (labels) look further for a clean patch
        for dy in range(-reach, reach + 1, 2):
            for dx in range(-reach, reach + 1, 2):
                if abs(dx) < (x1 - x0) and abs(dy) < (y1 - y0):
                    continue                                       # overlapping itself
                sy0, sx0 = y0 + dy, x0 + dx
                if sy0 < 0 or sx0 < 0 or sy0 + (y1 - y0) > h or sx0 + (x1 - x0) > w:
                    continue
                if busy[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)][g].any():
                    continue
                src = a[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)].astype(np.float32)
                score = float(((src[r] - target[r]) ** 2).mean()) if r.any() else 0.0
                score += 2.0 * (dx * dx + dy * dy) ** 0.5
                if best is None or score < best[0]:
                    best = (score, sy0, sx0)
        if best is None or (reach == 40 and best[0] > 1500):       # nothing clean, or no patch fits (a boat on a
            left |= piece                                          # winding river): Telea, which keeps the line
            continue
        if DEBUG: print('piece', x0, y0, x1 - x0, y1 - y0, 'score', round(best[0]), 'from', best[2] - x0, best[1] - y0)
        _, sy0, sx0 = best
        src = a[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)]
        out[y0:y1, x0:x1][p] = src[p]
    if left.any():
        out = cv2.cvtColor(cv2.inpaint(cv2.cvtColor(out, cv2.COLOR_RGB2BGR), left * 255, 3, cv2.INPAINT_TELEA),
                           cv2.COLOR_BGR2RGB)
    return out


def edit(name, rgb, src):
    """-> (edited RGB array, [what was removed]) for one map picture (name like 'z200' or 'z019_01')."""
    a = rgb.copy()
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    lum = (0.3 * r + 0.59 * g + 0.11 * b)
    gray = cv2.cvtColor(a, cv2.COLOR_RGB2GRAY).astype(np.float32)
    white = ((r > 205) & (g > 205) & (b > 195)).astype(np.uint8)   # label text, not the grey corridor stone
    yellow = ((r > 160) & (g > 110) & (b < 120) & (r - b > 70)).astype(np.uint8)
    mask = np.zeros(a.shape[:2], np.uint8)
    notes = []
    if name in BOAT_MAPS:
        tpl, tm = _boat_template(src)
        for x, y in _matches(gray, tpl, tm, 1500, (8, 6)):
            h, w = tpl.shape
            sprite = np.zeros_like(mask)
            sprite[y:y + h, x:x + w] = tm.astype(np.uint8)
            mask |= cv2.dilate(sprite, K3)
            notes.append(f'boat at {x},{y}')
        if name not in ROUTE_IS_RIVER:
            route = ((b > 150) & (b - r > 40) & (g > 110)).astype(np.uint8)
            mask |= cv2.dilate(route, K5)                          # the line and its dark-blue edging (on water)
            notes.append(f'boat routes ({int(route.sum())} px)')
    if name in EXTENSION_MAPS:
        strong = ((r > 120) & (r - g > 45) & (r - b > 45)).astype(np.uint8)
        weak = ((r > 70) & (r - g > 30) & (r - b > 28)).astype(np.uint8)
        weak = weak & (1 - cv2.morphologyEx(weak, cv2.MORPH_OPEN, K3))   # thin leader lines only, never reddish floors
        red = _reconstruct(strong, weak | strong)                  # names, ticks and their thin leader lines
        n_c, lab_c, stats, _ = cv2.connectedComponentsWithStats(strong)
        for k in range(1, n_c):                                    # entrance ticks: the whole little sprite
            x, y, w, h, area = stats[k]
            if area <= 40:
                red[max(0, y - 2):y + h + 2, max(0, x - 2):x + w + 2] = 1
        if red.any():
            mask |= _with_outline(red, lum)
            notes.append(f'extension labels / ticks ({int(red.sum())} px)')
        tpl, tm = _abandoned_template(src)
        boxes = [(x - 2, y - 2, x + tpl.shape[1] + 2, y + tpl.shape[0] + 2) for x, y in _matches(gray, tpl, tm, 2500, (20, 6))]
        boxes += ABANDONED_BOXES.get(name, [])
        n_lab, lab = cv2.connectedComponents(cv2.dilate(white, K5))    # whole labels (both lines: 2-px gaps join)
        for x0, y0, x1, y1 in boxes:
            x0, y0 = max(0, x0), max(0, y0)
            ids = set(np.unique(lab[y0:y1, x0:x1][white[y0:y1, x0:x1] > 0])) - {0}
            text = (np.isin(lab, list(ids)) & (white > 0)).astype(np.uint8)
            mask |= _with_outline(text, lum)
            ys, xs = np.nonzero(text)
            if len(xs):
                near = np.zeros_like(mask)                         # its yellow exit tick, just beside it
                near[max(0, ys.min() - 10):ys.max() + 10, max(0, xs.min() - 14):xs.max() + 14] = 1
                mask |= _with_outline(yellow & near, lum)
            notes.append(f'Abandoned Mines at {x0},{y0}')
    for box in CATACOMBS_BOXES.get(name, []):
        x0, y0, x1, y1 = box
        inside = np.zeros_like(mask)
        inside[y0:y1, x0:x1] = 1
        mask |= _with_outline(yellow & inside, lum) if (x1 - x0) * (y1 - y0) > 250 else inside   # a tick: all of it
        notes.append(f'Catacombs label {box}')
    if name in DOMES:
        tpl, tm = _dome_template(src)
        h, w = tpl.shape
        for x, y in DOMES[name]:
            sprite = np.zeros_like(mask)
            sprite[y:y + h, x:x + w] = tm[:max(0, min(h, a.shape[0] - y)), :max(0, min(w, a.shape[1] - x))]
            mask |= cv2.dilate(sprite, K3)
            notes.append(f'dome (no dungeon in 1.65) at {x},{y}')
    if name in SI_LABELS:
        (x0, y0, x1, y1), to, _ = SI_LABELS[name]
        m = np.zeros_like(mask)
        m[y0:y1, x0:x1] = _label_mask(a, (x0, y0, x1, y1))
        mask |= cv2.dilate(m, K3)
        notes.append(f'SI portal label moved to {to} (its 1.65 place)')
    for x0, y0, x1, y1 in TOWERS.get(name, []):
        mask[max(0, y0 - 2):y1 + 2, max(0, x0 - 2):x1 + 2] = 1
        notes.append(f'post-1.65 guard tower icon at {x0},{y0}')
    m = (mask > 0).astype(np.uint8)
    if not m.any():
        out = a
    elif name in OUTDOOR_FILL:                                 # outdoor maps: a patch of the map's own ground
        out = _patch_fill(a, m, lum)
    else:                                                      # dungeon / city plans: a patch could add corridors
        out = cv2.cvtColor(cv2.inpaint(cv2.cvtColor(a, cv2.COLOR_RGB2BGR), m * 255, 3, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
    road = (r > 140) & (g < 70) & (b < 70)
    for x0, y0, x1, y1 in TOWERS.get(name, []):               # a road that ran behind the icon: joined up again
        lx, rx = max(0, x0 - 3), min(a.shape[1] - 1, x1 + 2)
        ly = [y for y in range(y0 - 2, y1 + 2) if road[y, lx]]
        ry = [y for y in range(y0 - 2, y1 + 2) if road[y, rx]]
        if ly and ry:
            col = a[ly[0], lx]
            for x in range(lx + 1, rx):
                t = (x - lx) / (rx - lx)
                yy = round(ly[0] + (ry[0] - ly[0]) * t)
                out[yy:yy + max(len(ly), 1), x] = col
            notes.append(f'road behind the tower icon at {x0},{y0} joined')
    for (x0, y0, x1, y1), (tx, ty) in ICON_MOVES.get(name, []):
        piece = a[y0:y1, x0:x1]
        pl = (0.3 * piece[..., 0] + 0.59 * piece[..., 1] + 0.11 * piece[..., 2])
        sat = piece.max(axis=2).astype(int) - piece.min(axis=2)
        icon = (pl < 50) | ((sat < 40) & (pl > 100))               # the icon's black outline and grey-white body
        region = out[ty:ty + (y1 - y0), tx:tx + (x1 - x0)]
        region[icon] = piece[icon]
        notes.append(f'guard tower icon moved to {tx},{ty} (the 1.65 tower)')
    for source, (box, to, (tx, ty)) in SI_LABELS.items():
        if to != name:
            continue
        srgb = np.asarray(Image.open(src / f'{source}.png').convert('RGB'))
        lm = _label_mask(srgb, box).astype(bool)
        x0, y0, x1, y1 = box
        region = out[ty:ty + (y1 - y0), tx:tx + (x1 - x0)]
        piece = srgb[y0:y1, x0:x1][:region.shape[0], :region.shape[1]]
        sel = lm[:region.shape[0], :region.shape[1]]
        region[sel] = piece[sel]
        notes.append(f'SI portal label from {source} placed at {tx},{ty} (its 1.65 place)')
    return out, notes
