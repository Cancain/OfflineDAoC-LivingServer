"""Quests for a zone (ZONE CONTENT PROCESS.md steps 3-6): every classic data quest whose giver stands in the zone,
from the old OfflineDAoC project (read only): DataQuest rows (the vetted classic set, ClassicQuestStep), its
runtime/server/classic-quests.json (per-step map markers, event monsters, custom steps, the walkthroughs' keyword
dialogue) and classic-quest-guides.json (the owner's QUEST GUIDE: period Allakhazam walkthroughs). The engine runs
them with its own quest code (game/quests); nothing of the old server's code is used.

    python build_quests.py --zone=200
Merges into godot/content/quests/quests.json:
  quests: {id: {id, name, giver, giver_region, accept, description, min, max, classes, races, depends, max_count,
                steps: [{type, text, target, target_region, target_text, source_text, advance, step_item, step_chance,
                         collect, money, xp, marker, spawn, custom, needs_item, issuer, grant, grant_from, search}],
                final_rewards, optional_rewards, optional_choose, finish_text}}
  chat: {npc name: {keyword: reply}}, guides: {quest name: {source, updated, lines}},
  items: {id: item (build_items fields + icon)}, missing_items: [...]
Points (markers, search areas, spawns, custom places) are resolved to {zone, pos [x, y, z] metres}."""
import json, re, sqlite3, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from assets_pipeline import ROOT
from build_zone import zone_section, zone_of
from build_items import FIELDS, object_icons, global_icon, DB

OLD = ROOT / 'external/old_project'
CLASSIC = OLD / 'runtime/server/classic-quests.json'
GUIDES = OLD / 'runtime/server/classic-quest-guides.json'
OUT = ROOT / 'godot/content/quests/quests.json'
M = 0.025
# owner rulings: quests left out (2026-10-09: no period source anywhere - not on Allakhazam, Wayback or Warcry)
REMOVED_QUESTS = {'vial of glowing gasses -- kill task'}

# Event monsters the old data gives no model (model 0, no template) - judgement calls, listed in the zone ledger:
# Spicket is one of the three spraggon brothers of "Spicket, Spackit and Spykit"; Spackit and Spykit are model 112.
SPAWN_MODEL_FIX = {'Spicket': 112}

STEP_TYPES = {0: 'kill', 1: 'kill_finish', 2: 'deliver', 3: 'deliver_finish', 4: 'interact', 5: 'interact_finish',
              6: 'whisper', 7: 'whisper_finish', 8: 'search', 9: 'search_finish', 10: 'collect', 11: 'collect_finish'}


def split(v, sep='|'):
    return [] if v is None or str(v) == '' else str(v).split(sep)


def at(lst, i, default=''):
    return lst[i] if i < len(lst) else default


def point(region, x, y, z=0):
    """{zone, pos} for a region point, or None when no zone holds it."""
    z_ = zone_of(int(region), int(x), int(y))
    if z_ is None:
        return None
    zid, ox, oy = z_
    return {'zone': zid, 'pos': [round((x - ox) * M, 3), round(z * M, 3), round((y - oy) * M, 3)]}


def main():
    zone = int(next((a.split('=')[1] for a in sys.argv if a.startswith('--zone=')), 200))
    sec = dict(line.split('=', 1) for line in zone_section(zone).splitlines() if '=' in line)
    region = int(sec['region'])
    x0, y0 = int(sec['region_offset_x']) * 8192, int(sec['region_offset_y']) * 8192
    x1, y1 = x0 + int(sec['width']) * 8192, y0 + int(sec['height']) * 8192
    db = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    classic = json.loads(CLASSIC.read_text(encoding='utf-8'))
    guides = json.loads(GUIDES.read_text(encoding='utf-8')).get('Guides', {}) if GUIDES.exists() else {}
    out = json.loads(OUT.read_text(encoding='utf-8')) if OUT.exists() else {}
    for k in ('quests', 'chat', 'guides', 'items'):
        out.setdefault(k, {})
    missing = set(out.get('missing_items', []))
    givers = {r[0] for r in db.execute('select Name from Mob where Region=? and X>=? and X<? and Y>=? and Y<?',
                                       (region, x0, x1, y0, y1))}
    cols = [r[1] for r in db.execute('pragma table_info(DataQuest)')]
    want_items = set()
    n = 0
    for row in db.execute('select * from DataQuest where ID>=20000 and StartRegionID=?', (region,)):
        d = dict(zip(cols, row))
        if d['StartName'] not in givers or str(d['Name'] or '').strip().lower() in REMOVED_QUESTS:
            continue
        n += 1
        info = classic['Quests'].get(str(d['ID']), {})
        csteps = info.get('Steps', [])
        types = [int(t) for t in split(d['StepType'])]
        texts, sources = split(d['StepText']), split(d['SourceText'])
        targets, ttexts = split(d['TargetName']), split(d['TargetText'])
        advances, sitems, collects = split(d['AdvanceText']), split(d['StepItemTemplates']), split(d['CollectItemTemplate'])
        moneys, xps = split(d['RewardMoney']), split(d['RewardXP'])
        searches = {}
        for s in split(d['SourceName']):
            p = s.split(';')
            if p[0].upper() == 'SEARCH' and len(p) >= 8:      # SEARCH;step;text;region;x;y;radius;seconds
                pt = point(p[3], int(p[4]), int(p[5]))
                searches[int(p[1])] = {'text': p[2], **(pt or {}), 'radius_m': int(p[6]) * M, 'seconds': int(p[7])}
        steps = []
        for i, t in enumerate(types):
            tgt = at(targets, i).split(';') if at(targets, i) else ['', '0']
            item = at(sitems, i).strip()
            item_id, chance = (item.split(';') + [''])[:2] if item else ('', '')
            st = {'type': STEP_TYPES.get(t, 'unknown'), 'text': at(texts, i), 'target': tgt[0],
                  'target_region': int(tgt[1]) if len(tgt) > 1 and tgt[1].strip().isdigit() else 0,
                  'target_text': at(ttexts, i), 'source_text': at(sources, i), 'advance': at(advances, i),
                  'step_item': item_id, 'step_chance': int(chance) if chance.strip().isdigit() else 0,
                  'collect': at(collects, i).strip(), 'money': int(at(moneys, i, '0') or 0),
                  'xp': int(at(xps, i, '0') or 0)}
            for v in (item_id, st['collect']):
                if v:
                    want_items.add(v)
            if i + 1 in searches:
                st['search'] = searches[i + 1]
            c = csteps[i + 1] if i + 1 < len(csteps) and csteps[i + 1] else {}
            if c.get('Marker'):
                mk = c['Marker']
                st['marker'] = point(mk['Region'], mk['X'], mk['Y'], mk.get('Z', 0))
            if c.get('Spawn'):
                sp = c['Spawn']
                st['spawn'] = {'name': sp['Name'], 'template': sp.get('TemplateId', 0), 'level': sp.get('Level', 0),
                               'model': sp.get('Model', 0), 'count': sp.get('Count', 1),
                               'trigger_m': sp.get('TriggerRadius', 1500) * M, 'despawn': sp.get('DespawnSeconds', 600),
                               'peaceful': bool(sp.get('Peaceful', False)),
                               **({'model': SPAWN_MODEL_FIX[sp['Name']], 'model_fix': True}
                                  if not sp.get('Model') and not sp.get('TemplateId') and sp['Name'] in SPAWN_MODEL_FIX else {}),
                               **(point(sp['Region'], sp['X'], sp['Y'], sp.get('Z', 0)) or {})}
                tpl = db.execute('select Name, Model, Size, Level, MeleeDamageType, Strength, Constitution, Dexterity, '
                                 'Quickness, EquipmentTemplateID, BodyType from NpcTemplate where TemplateId=?',
                                 (sp.get('TemplateId', 0),)).fetchone() if sp.get('TemplateId') else None
                if tpl:
                    st['spawn']['npc_template'] = dict(zip(['name', 'model', 'size', 'level', 'damage_type', 'str', 'con',
                                                            'dex', 'qui', 'equipment', 'body_type'], tpl))
            if c.get('Custom'):
                cu = {k.lower(): v for k, v in c['Custom'].items() if v not in (None, '', [], {})}
                if cu.get('region'):
                    pt = point(cu['region'], cu.get('x', 0), cu.get('y', 0), cu.get('z', 0))
                    if pt:
                        cu.update(pt)
                    cu['radius_m'] = cu.get('radius', 600) * M
                for v in [cu.get('item')] + list((cu.get('trades') or {}).keys()) + list((cu.get('trades') or {}).values()) \
                        + list((cu.get('choices') or {}).values()) + [dr.get('Item') for dr in cu.get('drops') or []]:
                    if v:
                        want_items.add(v)
                st['custom'] = cu
            for k_src, k_dst in (('NeedsItem', 'needs_item'), ('Issuer', 'issuer'), ('GrantFrom', 'grant_from')):
                if c.get(k_src):
                    st[k_dst] = c[k_src]
            if c.get('Grant'):
                st['grant'] = c['Grant']
                want_items |= set(c['Grant'])
            if st.get('needs_item'):
                want_items.add(st['needs_item'])
            steps.append(st)
        opt = d['OptionalRewardItemTemplates'] or ''
        q = {'id': d['ID'], 'name': d['Name'], 'giver': d['StartName'], 'giver_region': d['StartRegionID'],
             'zone': zone, 'accept': d['AcceptText'] or '', 'description': d['Description'] or '',
             'min': d['MinLevel'] or 1, 'max': d['MaxLevel'] or 50,
             'classes': [int(c) for c in split(d['AllowedClasses']) if c.strip().isdigit()],
             'races': info.get('Races', []), 'depends': split(d['QuestDependency']),
             'max_count': 1, 'steps': steps,
             'final_rewards': split(d['FinalRewardItemTemplates']),
             'optional_choose': int(opt[0]) if opt[:1].isdigit() else 0,
             'optional_rewards': [s for s in split(opt[1:])] if opt[:1].isdigit() else [],
             'finish_text': d['FinishText'] or ''}
        want_items |= set(q['final_rewards']) | set(q['optional_rewards'])
        out['quests'][str(d['ID'])] = q
        realm = 'hibernia' if region >= 200 else ('midgard' if region >= 100 else 'albion')
        g = guides.get(f"{realm}|{d['Name'].lower()}")
        if g:
            out['guides'][d['Name']] = {'source': g.get('Source', ''), 'updated': g.get('Updated', ''), 'lines': g.get('Lines', [])}
    for name in givers:
        if name in classic.get('Chat', {}):
            out['chat'][name] = classic['Chat'][name]
    # every item the quests hand out, take or drop
    icons = object_icons()
    pq = OLD / 'development-source/research/period-data/quests'
    period_rewards = {r['Id_nb']: r for r in json.loads((pq / 'reward_item_rows.json').read_text(encoding='utf-8'))} \
        if (pq / 'reward_item_rows.json').exists() else {}
    period_report = json.loads((pq / 'reward_items_report.json').read_text(encoding='utf-8')).get('built', {}) \
        if (pq / 'reward_items_report.json').exists() else {}
    # this project's own pass first (build_reward_items.py: period pages -> Uthgard -> live Allakhazam)
    mine = HERE / 'data/reward_item_rows.json'
    if mine.exists():
        period_rewards.update({r['Id_nb']: r for r in json.loads(mine.read_text(encoding='utf-8'))})
        rep = json.loads((HERE / 'data/reward_items_report.json').read_text(encoding='utf-8')).get('built', {})
        period_report.update({k: {'source': f"{v['source']} {v.get('date', '')[:8]} {v.get('page', '')}".strip()}
                              for k, v in rep.items()})
    invented = set(json.loads((HERE / 'data/reward_items_report.json').read_text(encoding='utf-8')).get('invented', {}))         if (HERE / 'data/reward_items_report.json').exists() else set()
    fcols = ', '.join(FIELDS)
    for tid in list(want_items):                           # per-class rewards: every class's own item too
        want_items |= set(period_rewards.get(tid, {}).get('variants', {}).values())
    for tid in sorted(want_items):
        if tid in out['items'] and tid not in period_rewards:     # reward rows are rebuilt each run
            continue
        row = db.execute(f'select Id_nb, {fcols} from ItemTemplate where Id_nb=?', (tid,)).fetchone()
        if row is None and tid in period_rewards:
            # a classic quest reward with no DB template: the old project's period-built row (stats from the period
            # Allakhazam item page, Internet Archive; the 3D model borrowed from an item of the same slot / type -
            # period_data/quests/reward_items_report.json says which page and what was borrowed)
            pr = period_rewards[tid]
            row = tuple([tid] + [pr.get(f, 0 if f not in ('Name', 'AllowedClasses') else '') for f in FIELDS])
        if row is None:
            missing.add(tid)
            continue
        it = dict(zip(['id'] + [f.lower() for f in FIELDS], row))
        if tid in period_rewards:
            it['source'] = 'period reward page (' + period_report.get(tid, {}).get('source', '?') + ')'
            if period_rewards[tid].get('variants'):
                it['variants'] = period_rewards[tid]['variants']
            if tid in invented:
                it['source'] = 'stats made up (1.65 EXCEPTIONS MADE.txt)'

        it['icon'] = global_icon(icons.get(int(it['model'] or 0), -1))
        out['items'][tid] = it
    out['missing_items'] = sorted(missing - set(out['items']))
    out['source'] = ('old OfflineDAoC DataQuest + runtime/server/classic-quests.json + classic-quest-guides.json '
                     '(read only); quest code is the engine\'s own')
    import build_quest_xp                                   # period quest experience (by level), every quest
    build_quest_xp.apply(out)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=1), encoding='utf-8')
    print(f'zone {zone}: {n} quests, {len(out["quests"])} total, {len(out["chat"])} NPC chats, '
          f'{len(out["guides"])} guides, {len(out["items"])} items, missing {sorted(out["missing_items"])[:12]}')


if __name__ == '__main__':
    main()
