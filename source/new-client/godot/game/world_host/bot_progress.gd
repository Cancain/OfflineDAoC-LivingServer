class_name BotProgress
extends RefCounted
## A gamebot's progression the player's way (owner 2026-10-11, from the old server's lessons): it joins an advanced
## class at a trainer at level 5, trains its specialization points at its trainer by a plan of its own, loots its kills
## (coins and the monster's drops, the player's tables), wears what is better, sells between camps when its bag fills,
## buys an upgrade it can afford, buys its arrows, and picks its combat styles each swing.
## Errands (promote / train / sell / arrows) name a real NPC of its realm - in its zone or another outdoor zone of its
## region (the bot walks over the border); BotSim walks there and calls do_errand when it arrives.

const BLOCK_M := 204.8                       # a zones_index block (RegionWorld.BLOCK_M)
const TRAIN_EVERY := 3                       # levels of points saved before a trainer trip (players train every few)
const SELL_FREE_SLOTS := 6                   # backpack slots left that send it to sell (between camps only - never mid-grind)
const ARROWS_LOW := 15
const ARROWS_WANT := 60
const ARROW_TYPE := 43
const BOW_TYPES := [9, 15, 18]
const BOW_SPECS := ["Longbows", "Composite Bow", "Recurve Bow", "Archery"]
const DEFENCE := ["Shield", "Parry", "Evade"]
const STAT_KEYS := {"STR": 1, "CON": 3, "DEX": 2, "QUI": 4, "INT": 5, "PIE": 6, "EMP": 7, "CHA": 8}   # eProperty
const ARMOR_SLOTS := [21, 22, 23, 25, 27, 28]

static var _index := {}
static var _services := {}                   # zone id -> [{role, trains, realm, pos, name, items}]
static var _arrow_lists := {}                # merchant list id -> [arrow item ids]


# ---------------------------------------------------------------- the world's trainers and merchants (static data)

static func _load_index() -> void:
	if not _index.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json")) \
			if FileAccess.file_exists("res://content/zones/zones_index.json") else null
	_index = parsed if parsed is Dictionary else {}


static func _zone_services(zid: int) -> Array:
	if _services.has(zid):
		return _services[zid]
	var out := []
	var path := "res://content/zones/zone%03d/npcs.json" % zid
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		var spawns = d.get("spawns", []) if d is Dictionary else []
		if spawns is Dictionary:
			spawns = spawns.values()
		for s in spawns:
			if not (s is Dictionary):
				continue
			var role := String(s.get("role", ""))
			var items := str(s.get("items", "")) if s.get("items") != null else ""
			if role != "trainer" and items == "":
				continue
			var p: Array = s.get("pos", [0, 0, 0])
			out.append({"role": role, "trains": ClassDb.by_name(str(s.get("trains", "")) if s.get("trains") != null else ""),
					"realm": int(s.get("realm", 0)), "pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
					"name": String(s.get("name", "")), "items": items})
	_services[zid] = out
	return out


## The outdoor zones of a zone's region, the zone itself first.
static func _region_zones(zid: int) -> Array:
	_load_index()
	var me: Dictionary = _index.get(str(zid), {})
	var out := [zid]
	if me.is_empty() or int(me.get("type", 0)) != 0:
		return out
	for k in _index:
		var z: Dictionary = _index[k]
		if int(k) != zid and int(z.get("region", -1)) == int(me.region) and int(z.get("type", 0)) == 0 and bool(z.get("built", false)):
			out.append(int(k))
	return out


## A point of zone `to` in zone `from`'s frame (metres).
static func local_in(from: int, to: int, pos: Vector3) -> Vector3:
	_load_index()
	var a: Dictionary = _index.get(str(from), {})
	var b: Dictionary = _index.get(str(to), {})
	if a.is_empty() or b.is_empty():
		return pos
	return pos + Vector3((float(b.x) - float(a.x)) * BLOCK_M, 0.0, (float(b.y) - float(a.y)) * BLOCK_M)


## The outdoor zone of `from`'s region under a point in `from`'s frame, and the point in its own frame; {} outside.
static func zone_at(from: int, local: Vector3) -> Dictionary:
	_load_index()
	var me: Dictionary = _index.get(str(from), {})
	if me.is_empty():
		return {}
	var gx := float(me.x) + local.x / BLOCK_M
	var gy := float(me.y) + local.z / BLOCK_M
	for k in _index:
		var it: Dictionary = _index[k]
		if int(it.get("region", -1)) != int(me.region) or int(it.get("type", 0)) != 0 or not bool(it.get("built", false)):
			continue
		if gx >= float(it.x) and gy >= float(it.y) and gx < float(it.x) + float(it.w) and gy < float(it.y) + float(it.h):
			return {"zone": int(k), "pos": local_in(int(k), from, local)}
	return {}


# ---------------------------------------------------------------- what it is working towards

static func _info(b: BotFoe) -> Dictionary:
	var c: Dictionary = b.sheet.character
	if not (c.get("bot") is Dictionary):
		c["bot"] = {}
	return c["bot"]


static func _hash(b: BotFoe, salt: String) -> int:
	return absi(hash("%d:%s" % [b.id, salt]))


## The advanced class a base-class bot will join (fixed per bot): one its race may take and whose trainer its region has.
static func promotion_class(b: BotFoe, zid: int) -> int:
	var sh := b.sheet
	var cid := sh.class_id()
	var c := ClassDb.cls(cid)
	if not bool(c.get("is_base", false)):
		return 0
	var info := _info(b)
	if int(info.get("plan_class", 0)) > 0:
		return int(info.plan_class)
	var race := String(sh.character.get("race", ""))
	var offered := {}
	for z in _region_zones(zid):
		for s in _zone_services(z):
			if s.role == "trainer" and int(s.realm) == sh.realm_id():
				offered[int(s.trains)] = true
	var choices := []
	for a in c.get("advanced", []):
		if ClassDb.can_promote(int(a), cid, 5, race) and offered.has(int(a)):
			choices.append(int(a))
	if choices.is_empty():
		return 0
	var pick: int = choices[_hash(b, "class") % choices.size()]
	info["plan_class"] = pick
	return pick


static func needs_training(b: BotFoe) -> bool:
	var sh := b.sheet
	if bool(ClassDb.cls(sh.class_id()).get("is_base", true)):
		return false
	var pts := sh.spec_points()
	if pts <= 0:
		return false
	var trained := int(_info(b).get("trained_level", 0))
	if sh.level - trained < TRAIN_EVERY and sh.level < 50 and trained > 0:
		return false
	for e in plan(b):
		var k := String(e[0])
		if float(e[1]) > 0.0 and sh.specs.has(k) and int(sh.specs[k]) < sh.level and int(sh.specs[k]) + 1 <= pts:
			return true
	return false


static func arrow_count(b: BotFoe) -> int:
	var n := 0
	for slot in range(CharacterState.BACKPACK, CharacterState.BACKPACK_END + 1):
		var e := b.sheet.entry(slot)
		if not e.is_empty() and int(ItemDb.item(String(e.id)).get("object_type", 0)) == ARROW_TYPE:
			n += int(e.get("count", 1))
	return n


static func uses_bow(b: BotFoe) -> bool:
	var bow := b.sheet.item_at(13)
	return not bow.is_empty() and int(bow.get("object_type", 0)) in BOW_TYPES and b.sheet.can_use(bow) \
			and MeleeMath.spec_level(b.sheet, CombatRules.weapon_spec_key(bow)) > 0


static func _arrows_in(list: String) -> Array:
	if not _arrow_lists.has(list):
		var ids := []
		for e in ItemDb.merchant_list(list):
			if int(ItemDb.item(String(e[2])).get("object_type", 0)) == ARROW_TYPE:
				ids.append(String(e[2]))
		_arrow_lists[list] = ids
	return _arrow_lists[list]


## Its next errand, or {}: {kind, zone, pos (that zone's frame), local (this zone's frame), name, want}. Blocked kinds
## (a recent failure, BotFoe.errand_blocked) are skipped.
static func errand(b: BotFoe, zid: int) -> Dictionary:
	if b.has_meta("companion"):
		return {}
	var sh := b.sheet
	var kind := ""
	var want := 0
	if sh.level >= 5 and bool(ClassDb.cls(sh.class_id()).get("is_base", false)):
		kind = "promote"
		want = promotion_class(b, zid)
		if want == 0:
			return {}
	elif needs_training(b):
		kind = "train"
		want = sh.class_id()
	elif sh.free_slots() <= SELL_FREE_SLOTS and not sellables(b).is_empty():
		kind = "sell"
	elif uses_bow(b) and arrow_count(b) < ARROWS_LOW and sh.free_slots() > 0:
		kind = "arrows"
	if kind == "" or b.errand_blocked(kind):
		return {}
	var money := sh.total_copper()
	var best := {}
	var best_d := INF
	for z in _region_zones(zid):
		for s in _zone_services(z):
			if int(s.realm) != sh.realm_id() and not (kind in ["sell", "arrows"] and int(s.realm) == 0):
				continue
			match kind:
				"promote", "train":
					if s.role != "trainer" or int(s.trains) != want:
						continue
				"sell":
					if String(s.items) == "":
						continue
				"arrows":
					if String(s.items) == "" or not _arrows_in(String(s.items)).any(func(id): return int(ItemDb.item(String(id)).get("price", 0)) <= money):
						continue
			var local := local_in(zid, int(z), s.pos)
			var d := local.distance_squared_to(b.pos)
			if d < best_d:
				best_d = d
				best = {"kind": kind, "zone": int(z), "pos": s.pos, "local": local, "name": s.name, "want": want}
	return best


# ---------------------------------------------------------------- at the trainer / merchant

## The errand done at the NPC it walked to (nearest live NPC of that role within 12 m). The result for its log, "" when
## nothing could be done.
static func do_errand(npcs: NpcManager, b: BotFoe, kind: String, want: int) -> String:
	var npc: NpcState = null
	var bd := 144.0
	for s in npcs.states:
		var st: NpcState = s
		var role := String(st.spawn.get("role", ""))
		var ok := role == "trainer" if kind in ["promote", "train"] else str(st.spawn.get("items", "")) not in ["", "<null>"]
		if not ok:
			continue
		var d := st.pos.distance_squared_to(b.pos)
		if d < bd:
			bd = d
			npc = st
	if npc == null:
		return ""
	var sh := b.sheet
	var who := String(npc.spawn.get("name", ""))
	match kind:
		"promote":
			if ClassDb.can_promote(want, sh.class_id(), sh.level, String(sh.character.get("race", ""))):
				sh.promote(want)
				var trained := spend(b)
				return "joined the %s at %s%s" % [String(ClassDb.cls(want).get("name", "")), who, (", trained " + trained) if trained != "" else ""]
		"train":
			var trained := spend(b)
			if trained != "":
				return "trained %s at %s" % [trained, who]
		"sell":
			return sell_at(b, npc)
		"arrows":
			var got := buy_arrows(b, npc)
			if got > 0:
				return "bought %d arrows from %s" % [got, who]
	return ""


## Its specialization plan (fixed per bot): [[spec, ratio], ...] - a main line to its level, a second at 60%, a third at
## 35% (the old server's BotSpec idea): casters a magic line, hybrids their weapon then a magic line, tanks their weapon
## then a defence, archers their bow first.
static func plan(b: BotFoe) -> Array:
	var sh := b.sheet
	var info := _info(b)
	var cid := sh.class_id()
	if info.get("plan") is Array and int(info.get("plan_for", 0)) == cid:
		return info.plan
	var keys := []
	for e in ClassDb.trainable_specs(cid, 50):
		if not ClassDb.cls(cid).get("autotrain", []).has(String(e.spec)):
			keys.append(String(e.spec))
	var magic := keys.filter(func(k): return ClassDb.spec_has_line(k))
	var bows := keys.filter(func(k): return k in BOW_SPECS)
	var defence := keys.filter(func(k): return k in DEFENCE)
	var w := MeleeMath.weapon(sh)
	var weapon := CombatRules.weapon_spec_key(w) if not w.is_empty() else ""
	if not (weapon in keys):
		var others := keys.filter(func(k): return not (k in magic) and not (k in bows) and not (k in defence))
		weapon = String(others[_hash(b, "weapon") % others.size()]) if not others.is_empty() else ""
	var picks := []
	var kind := String(ClassDb.cls(cid).get("class_type", ""))
	var pick_from := func(list: Array, salt: String) -> String:
		var rest := list.filter(func(k): return not (k in picks))
		return String(rest[_hash(b, salt) % rest.size()]) if not rest.is_empty() else ""
	if not bows.is_empty() and kind != "ListCaster":
		picks.append(bows[0])
		if weapon != "":
			picks.append(weapon)
		var t: String = pick_from.call(defence + magic, "third")
		if t != "":
			picks.append(t)
	elif kind == "ListCaster" and not magic.is_empty():
		picks.append(pick_from.call(magic, "main"))
		var s2: String = pick_from.call(magic, "second")
		if s2 != "":
			picks.append(s2)
		var s3: String = pick_from.call(magic, "third")
		if s3 != "":
			picks.append(s3)
	else:
		if weapon != "":
			picks.append(weapon)
		var s2: String = pick_from.call(magic if not magic.is_empty() else defence, "second")
		if s2 != "":
			picks.append(s2)
		var s3: String = pick_from.call(defence if not magic.is_empty() else keys, "third")
		if s3 != "":
			picks.append(s3)
	var ratios := [1.0, 0.6, 0.35]
	var out := []
	for i in picks.size():
		if picks[i] != "":
			out.append([picks[i], ratios[mini(i, 2)]])
	info["plan"] = out
	info["plan_for"] = cid
	return out


## Spends its points by its plan at a trainer (CharacterState.train - the player's rule and costs). The trained levels
## for its log ("Slash 12, Shield 7"), "" when nothing was trained.
static func spend(b: BotFoe) -> String:
	var sh := b.sheet
	var p := plan(b)
	var done := {}
	for _guard in 400:
		var best := ""
		var best_need := INF
		for e in p:
			var k := String(e[0])
			if not sh.specs.has(k):
				continue
			var cur := int(sh.specs[k])
			var target := maxi(1, int(sh.level * float(e[1])))
			if cur >= target or cur >= sh.level or sh.spec_points() < cur + 1:
				continue
			var need := float(cur) / float(target)
			if need < best_need:
				best_need = need
				best = k
		if best == "":
			break
		if not sh.train(best):
			break
		done[best] = int(sh.specs[best])
	# what is left goes on the main line while it can
	if not p.is_empty():
		var main := String(p[0][0])
		while sh.specs.has(main) and int(sh.specs[main]) < sh.level and sh.spec_points() >= int(sh.specs[main]) + 1:
			if not sh.train(main):
				break
			done[main] = int(sh.specs[main])
	_info(b)["trained_level"] = sh.level
	var parts := []
	for k in done:
		parts.append("%s %d" % [k, done[k]])
	return ", ".join(parts)


# ---------------------------------------------------------------- gear

## How good an item is for this character (higher is better; -1 it can't use it): armour by its factor and absorb,
## weapons by damage per second (its trained weapon kinds count fully), bonuses weighted by its class's stats.
static func item_score(sh: CharacterState, it: Dictionary) -> float:
	if it.is_empty():
		return 0.0
	if not sh.can_use(it):
		return -1.0
	var q := float(it.get("quality", 85)) / 100.0
	var ot := int(it.get("object_type", 0))
	var s := float(it.get("level", 0)) * 0.5
	if ot >= 32 and ot <= 38:                                  # armour
		s += float(it.get("dps_af", 0)) * q * (1.0 + float(it.get("spd_abs", 0)) / 100.0)
	elif ot == ItemDb.SHIELD_TYPE:
		s += float(it.get("dps_af", 0)) * q + float(it.get("level", 0))
	elif CombatRules.weapon_spec_key(it) != "":
		var trained := MeleeMath.spec_level(sh, CombatRules.weapon_spec_key(it)) > 0
		s += float(it.get("dps_af", 0)) * q * (1.0 if trained else 0.4)
	var c := ClassDb.cls(sh.class_id())
	var weights := {}
	weights[int(STAT_KEYS.get(String(c.get("primary", "")), 0))] = 3.0
	weights[int(STAT_KEYS.get(String(c.get("secondary", "")), 0))] = 2.0
	weights[int(STAT_KEYS.get(String(c.get("tertiary", "")), 0))] = 1.5
	for i in range(1, 11):
		var t := int(it.get("bonus%dtype" % i, 0))
		var v := float(it.get("bonus%d" % i, 0))
		if t == 0 or v == 0.0:
			continue
		if t == 10:
			s += v * 0.25                                      # hit points
		elif t >= 1 and t <= 8:
			s += v * float(weights.get(t, 1.0))
		elif t >= 11 and t <= 19:
			s += v * 0.8                                       # resists
		else:
			s += v * 0.5
	return s


## The worn slot an item would go to and what it replaces: only the hands it fights with (its active weapon set), a
## shield only where a shield is, a bow only if it trains bows.
static func _target_slot(b: BotFoe, it: Dictionary) -> int:
	var sh := b.sheet
	var slots := sh.slots_for(it)
	if slots.is_empty():
		return -1
	var t := int(it.get("item_type", 0))
	if t == 12 and sh.active_weapon != "twohand":
		return -1
	if t == 10 and sh.active_weapon != "standard":
		return -1
	if t == 13 and not (int(it.get("object_type", 0)) in BOW_TYPES and MeleeMath.spec_level(sh, CombatRules.weapon_spec_key(it)) > 0):
		return -1
	if t == 11:
		var left := sh.item_at(11)
		var shield := int(it.get("object_type", 0)) == ItemDb.SHIELD_TYPE
		if sh.active_weapon != "standard":
			return -1
		if not shield and not bool(ClassDb.cls(sh.class_id()).get("left_hand", false)):
			return -1                                          # (no off-hand weapons without the left-hand ability)
		if not left.is_empty() and (int(left.get("object_type", 0)) == ItemDb.SHIELD_TYPE) != shield:
			return -1                                          # never trade a shield for a weapon or back (old swap loop)
		return 11
	var best := -1
	var worst := INF
	for s in slots:
		var cur := item_score(sh, sh.item_at(s))
		if sh.item_at(s).is_empty():
			return s
		if cur < worst:
			worst = cur
			best = s
	return best


## Puts on anything in its backpack better than what it wears (10% and a point better, so it never flips back and
## forth). The names it put on.
static func equip_upgrades(b: BotFoe) -> Array:
	var sh := b.sheet
	var put := []
	for _round in 3:
		var changed := false
		for slot in range(CharacterState.BACKPACK, CharacterState.BACKPACK_END + 1):
			var it := sh.item_at(slot)
			if it.is_empty():
				continue
			var to := _target_slot(b, it)
			if to < 0:
				continue
			var new_s := item_score(sh, it)
			if new_s < 0.0:
				continue
			var cur := sh.item_at(to)
			if not cur.is_empty() and new_s <= item_score(sh, cur) * 1.1 + 1.0:
				continue
			if sh.move(slot, to):
				put.append(String(it.get("name", "")))
				changed = true
		if not changed:
			break
	if not put.is_empty():
		sh.recalc_max()
	return put


## Backpack items it doesn't need: not arrows, not an upgrade, not the best spare of a weapon kind it can use, not
## something no merchant buys.
static func sellables(b: BotFoe) -> Array:
	var sh := b.sheet
	var keep_best := {}
	for slot in range(CharacterState.BACKPACK, CharacterState.BACKPACK_END + 1):
		var it := sh.item_at(slot)
		if it.is_empty() or CombatRules.weapon_spec_key(it) == "" or item_score(sh, it) < 0.0:
			continue
		var kind := int(it.get("object_type", 0))
		if not keep_best.has(kind) or item_score(sh, it) > item_score(sh, sh.item_at(int(keep_best[kind]))):
			keep_best[kind] = slot
	var out := []
	for slot in range(CharacterState.BACKPACK, CharacterState.BACKPACK_END + 1):
		var it := sh.item_at(slot)
		if it.is_empty() or int(it.get("object_type", 0)) in [ARROW_TYPE, 44]:
			continue
		if int(it.get("isdropable", 1)) == 0 or int(it.get("price", 0)) <= 0 or keep_best.values().has(slot):
			continue
		var to := _target_slot(b, it)
		if to >= 0 and item_score(sh, it) > item_score(sh, sh.item_at(to)):
			continue
		out.append(slot)
	return out


## At a merchant: sells what it doesn't need, then buys the best upgrade on the merchant's list it can spare the money
## for (half its purse) and puts it on.
static func sell_at(b: BotFoe, npc: NpcState) -> String:
	var sh := b.sheet
	var who := String(npc.spawn.get("name", ""))
	var before := sh.total_copper()
	var n := 0
	for slot in sellables(b):
		if sh.sell(slot, who):
			n += 1
	var earned := sh.total_copper() - before
	var bought := ""
	var list := str(npc.spawn.get("items", ""))
	var best := ""
	var gain := 0.0
	for e in ItemDb.merchant_list(list):
		var id := String(e[2])
		var it := ItemDb.item(id)
		var price := int(it.get("price", 0))
		if price <= 0 or price > sh.total_copper() / 2:
			continue
		var to := _target_slot(b, it)
		if to < 0:
			continue
		var s := item_score(sh, it)
		var cur := item_score(sh, sh.item_at(to))
		if s > cur * 1.1 + 1.0 and s - cur > gain:
			gain = s - cur
			best = id
	if best != "" and sh.buy(best, who):
		var put := equip_upgrades(b)
		bought = ", bought %s" % String(ItemDb.item(best).get("name", best)) + (" and put it on" if not put.is_empty() else "")
	if n == 0 and bought == "":
		return ""
	return "sold %d items at %s for %d copper%s" % [n, who, earned, bought]


static func buy_arrows(b: BotFoe, npc: NpcState) -> int:
	var sh := b.sheet
	var ids := _arrows_in(str(npc.spawn.get("items", "")))
	var got := 0
	while arrow_count(b) < ARROWS_WANT and sh.free_slots() > 0:
		var money := sh.total_copper()
		var pick := ""
		var pick_price := -1
		var cheap := ""
		var cheap_price := 1 << 60
		for id in ids:
			var price := int(ItemDb.item(String(id)).get("price", 0))
			if price <= money / 4 and price > pick_price:
				pick = String(id)
				pick_price = price
			if price <= money and price < cheap_price:
				cheap = String(id)
				cheap_price = price
		if pick == "":
			pick = cheap
		if pick == "":
			break
		var before := arrow_count(b)
		if not sh.buy(pick, String(npc.spawn.get("name", ""))):
			break
		got += arrow_count(b) - before
	return got


## Its kill's loot, the player's rules (Loot.on_kill): the coins (the monster's coin chance, Loot.money_for) and each
## item drop by its chance, into its purse and backpack; then anything better goes on. Companions loot nothing (yours).
static func loot(b: BotFoe, st: NpcState) -> String:
	if b.has_meta("companion"):
		return ""
	var d: Dictionary = (Loot.data().get("drops", {}) as Dictionary).get(String(st.spawn.name).to_lower(), {})
	var coins = d.get("coins") if not d.is_empty() else null
	var sh := b.sheet
	if coins == null or randf() * 100.0 < float(coins):
		sh.set_copper(sh.total_copper() + Loot.money_for(int(st.level)))
	var got := []
	for e in d.get("items", []):
		if randf() * 100.0 < float(e[1]) and sh.give_item(String(e[0]), "", true):
			got.append(String(ItemDb.item(String(e[0])).get("name", e[0])))
	if got.is_empty():
		return ""
	var put := equip_upgrades(b)
	return "looted %s%s" % [", ".join(got), (" and put on " + ", ".join(put)) if not put.is_empty() else ""]


# ---------------------------------------------------------------- styles

## The best style it may use on this swing (a gamebot with no tactics bar): a follow-up to the style that just landed,
## a reactive style after the monster's evade / parry / block / its own, a positional one when standing right, else the
## best anytime style by growth rate (the old "highest level" pick chose weak utility styles). Endurance permitting.
static func auto_style(combat: Combat, b: BotFoe, st: NpcState, w: Dictionary) -> Dictionary:
	var sh := b.sheet
	var sum := 0
	for k in sh.specs:
		sum += int(sh.specs[k])
	var key := "%d|%d" % [sh.class_id(), sum]
	if String(b.get_meta("styles_key", "")) != key:
		b.set_meta("styles_key", key)
		b.set_meta("styles", ClassDb.styles_known(sh.class_id(), sh.specs).filter(func(s): return not bool(s.get("stealthrequirement", false))))
	var best := {}
	var best_rank := -1.0
	for s in b.get_meta("styles", []):
		var style: Dictionary = s
		var cost := maxi(1, int(CombatRules.style_endurance(style, int(w.get("spd_abs", 30)))))
		if sh.end_pts < cost or not combat._bot_style_ok(b, style, st, w):
			continue
		var t := int(style.get("openingrequirementtype", 0))
		var v := int(style.get("openingrequirementvalue", 0))
		var tier := 1.0
		if t == 0 and v != 0:
			tier = 4.0                                         # a chain follow-up
		elif t == 1 and int(style.get("attackresultrequirement", 0)) != 0:
			tier = 3.0                                         # reactive
		elif t == 2:
			tier = 3.0                                         # positional
		elif int(style.get("attackresultrequirement", 0)) != 0:
			tier = 2.0                                         # after its own hit / miss
		var rank := tier * 1000.0 + float(style.get("growthrate", 0)) * 100.0 + float(style.get("speclevelrequirement", 0))
		if rank > best_rank:
			best_rank = rank
			best = style
	return best
