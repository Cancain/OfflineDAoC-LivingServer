class_name Companions
extends Node
## Companions (bot plan phase 6, owner 2026-10-10 / 11): adventurers you hire at your realm's roadside inn who travel
## and fight at your side - characters like you (their own CharacterState: stats, levels, specs, gear, the same rules),
## named and permanent, kept on your character (character["companions"]).
##   - Hiring at the innkeeper: always level 5, your choice of race, advanced class, gender, name and look; it comes
##     with a generic level-5 weapon of its class, no armour, no shield.
##   - Slots: the first opens at your level 5, then 15 / 25 / 35 / 45 / 50 / 50 (seven companions = a full group of
##     eight at 50). The hire cost rises with the companions you have: the first is free (placeholder costs - BOT
##     QUESTIONS.md).
##   - Dismiss: back to the inn with everything it carries; bring it back from the innkeeper for nothing.
##   - Permanent release: gone for good - anything still on it is lost; the slot takes a fresh level-5 hire (and its
##     cost) again.
##   - Death: it lies where it fell; any healer of your realm (the inns' own too) brings it back - free below level 20,
##     then for what a player of its level pays to have one death's constitution restored.
##   - Experience: the player-and-companion rate (not the gamebots'); kills share out across the group (group_xp).
##   - Regeneration, movement, combat: the player's rules (BotFoe / MeleeMath / BotSim - the companion brain).
## The level-5 courier (owner): the quest to the inn is handed to you the moment you reach level 5 - in a fight, dead,
## zoning, logging out and back in, skipping levels - whatever happens; the courier creature that brings it is only for
## the look (it can't be fought, killed or stuck: Courier).

signal changed                                   # the roster changed (the innkeeper / companion windows refresh)

const SLOT_LEVELS := [5, 15, 25, 35, 45, 50, 50]
const HIRE_COST := [0, 10000, 50000, 200000, 750000, 2500000, 5000000]   # copper by companions already hired (placeholder)
const HIRE_LEVEL := 5
const STANCES := ["aggressive", "supportive", "defensive", "passive"]
const BAG_FIRST := 40                            # the companion's 10 weightless bag slots: its backpack 40-49
const BAG_SLOTS := 10
const ID_BASE := 9000000                         # companion ids (never a gamebot's)
const QUEST_ID := {"hib": 90001, "mid": 90002, "alb": 90003}
const GROUP_RANGE := 2000 * 0.025                # experience reaches group members within 2000 units
const SHARE_BONUS := 0.125                       # each member past the first adds this much to a kill (group bonus)

var viewer: Node
var inns := {}                                   # content/companions/inns.json
var _foes := {}                                  # companion id -> BotFoe while it is in the world with you
var _group_left := 0.0
var _courier_left := -1.0                        # seconds until the courier may show (out of combat, alive)
var _courier: Node3D


func setup(v: Node) -> void:
	viewer = v
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/inns.json"))
	inns = (parsed as Dictionary).get("inns", {}) if parsed is Dictionary else {}
	_register_quests()
	PlayerData.leveled_up.connect(func(_lv): _check_courier())
	_check_courier.call_deferred()                 # logged in at 5+ without the quest yet: it comes now


# --- the roster -------------------------------------------------------------------------------------------------

static func roster() -> Array:
	if not (PlayerData.character.get("companions") is Array):
		PlayerData.character["companions"] = []
	return PlayerData.character.companions


static func info(rec: Dictionary) -> Dictionary:
	if not (rec.get("companion") is Dictionary):
		rec["companion"] = {}
	return rec.companion


static func by_id(id: int) -> Dictionary:
	for r in roster():
		if int(info(r).get("id", -1)) == id:
			return r
	return {}


func slots_open() -> int:
	return SLOT_LEVELS.filter(func(l): return PlayerData.level >= int(l)).size()


func hire_cost() -> int:
	return int(HIRE_COST[mini(roster().size(), HIRE_COST.size() - 1)])


## Why you can't hire right now ("" = you can).
func hire_problem() -> String:
	if PlayerData.level < HIRE_LEVEL:
		return "Companions join adventurers of level %d and above." % HIRE_LEVEL
	if roster().size() >= slots_open():
		var nxt := SLOT_LEVELS.filter(func(l): return int(l) > PlayerData.level)
		return "You have all the companions you can lead for now." + (" Another joins you at level %d." % int(nxt[0]) if not nxt.is_empty() else "")
	if PlayerData.total_copper() < hire_cost():
		return "Hiring costs %s." % PlayerData.money_string(hire_cost())
	return ""


## The name rules of character creation, and no clash with your characters, your companions or the gamebots.
static func name_problem(name: String) -> String:
	var p := CharacterStore.check_name(Accounts.account, name)
	if p != "":
		return p
	for r in roster():
		if String(r.get("name", "")).to_lower() == name.to_lower():
			return "You already have a companion named %s." % r.name
	var bots = JSON.parse_string(FileAccess.get_file_as_string(RealmSettings.BOT_ROSTER_PATH)) if FileAccess.file_exists(RealmSettings.BOT_ROSTER_PATH) else null
	if bots is Array:
		for b in bots:
			if b is Dictionary and String(b.get("name", "")).to_lower() == name.to_lower():
				return "That name is taken."
	return ""


## The advanced classes a race may be in 1.65 (the class's races, the base class the race / class pair starts from).
static func classes_for(realm: String, race_i: int) -> Array:
	var race: String = CharacterFactory.RACES[realm][race_i][0]
	var out := []
	var base_keys := {}
	for b in CharacterFactory.BASES[realm]:
		if CharacterFactory.available(realm, race_i, b):
			base_keys[ClassDb.by_name(String(CharacterFactory.BASE_CLASS[b]))] = b
	for id in range(1, 80):
		var c := ClassDb.cls(id)
		if c.is_empty() or bool(c.get("is_base", false)) or not base_keys.has(int(c.get("base_class", 0))):
			continue
		if String(c.get("realm", "")).left(3) != {"alb": "alb", "mid": "mid", "hib": "hib"}[realm]:
			continue
		var races: Array = c.get("races", [])
		if races.is_empty() or races.any(func(r): return String(r).to_lower() == race.to_lower()):
			out.append({"id": id, "name": String(c.name), "base": String(base_keys[int(c.base_class)])})
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return out


## A new companion's record: a level-5 character of the chosen race / class (made the way every character is -
## CharacterFactory), joined to its advanced class, its specs autotrained, a generic level-5 weapon of its class in hand.
func make(race_i: int, gender: int, class_id: int, name: String, look: Dictionary) -> Dictionary:
	var realm := PlayerData.realm_key()
	var c := ClassDb.cls(class_id)
	var base := ""
	for b in CharacterFactory.BASES[realm]:
		if ClassDb.by_name(String(CharacterFactory.BASE_CLASS[b])) == int(c.get("base_class", 0)):
			base = b
	var rec := CharacterFactory.make(realm, race_i, gender, base, name, look)
	rec["class_id"] = class_id
	rec["class_name"] = String(c.get("name", ""))
	rec["level"] = HIRE_LEVEL
	rec["xp"] = CombatRules.xp_for_level(HIRE_LEVEL)
	rec["inventory"] = {}
	var w := generic_weapon(class_id, int(c.get("base_class", 0)))
	if not w.is_empty():
		var slot := 12 if int(ItemDb.item(w).get("item_type", 10)) == 12 else (13 if int(ItemDb.item(w).get("item_type", 10)) == 13 else 10)
		rec["inventory"][str(slot)] = {"id": w, "count": 1}
		rec["active_weapon"] = {10: "standard", 12: "twohand", 13: "ranged"}[slot]
	return rec


## The class's generic level-5 weapon: its starting kit's weapon kind (the old server's StarterEquipment), the
## realm's merchant weapon of that kind closest to level 5 (at most 5) that the class may use; else the kit's own.
func generic_weapon(class_id: int, base_class: int) -> String:
	var kit := ""
	for id in ItemDb.starter(base_class):
		var it := ItemDb.item(id)
		if int(it.get("object_type", 0)) != ItemDb.SHIELD_TYPE and int(it.get("item_type", 0)) in [10, 11, 12, 13]:
			kit = String(id)
			break
	if kit == "":
		return ""
	var kind := int(ItemDb.item(kit).get("object_type", 0))
	var probe := CharacterState.new()                    # the class's rules, at level 5
	probe.character = {"class_id": class_id, "realm": PlayerData.realm_key(), "base": ""}
	probe.level = HIRE_LEVEL
	var best := kit
	var best_lv := -1
	for id in ItemDb.all_merchant_items():
		var it := ItemDb.item(String(id))
		var lv := int(it.get("level", 0))
		if int(it.get("object_type", 0)) != kind or lv > HIRE_LEVEL or lv <= best_lv:
			continue
		if int(it.get("realm", 0)) not in [0, PlayerData.realm_id()] or not probe.can_use(it):
			continue
		best = String(id)
		best_lv = lv
	probe.free()
	return best


## Hire: paid, on your roster, and at your side at once (you're at the inn).
func hire(race_i: int, gender: int, class_id: int, name: String, look: Dictionary, keeper: String) -> bool:
	var p := hire_problem()
	if p == "":
		p = name_problem(name)
	if p != "":
		PlayerData.message.emit(p, "error")
		return false
	var cost := hire_cost()
	var rec := make(race_i, gender, class_id, name, look)
	var n := int(PlayerData.character.get("companion_next_id", 1))
	PlayerData.character["companion_next_id"] = n + 1
	rec["companion"] = {"id": ID_BASE + n, "state": "with", "stance": "aggressive", "tactics": [], "upkeep": true,
			"hired": int(Time.get_unix_time_from_system())}
	if cost > 0:
		PlayerData.set_copper(PlayerData.total_copper() - cost)
		PlayerData.message.emit("You give %s %s." % [keeper, PlayerData.money_string(cost)], "merchant")
	roster().append(rec)
	PlayerData.message.emit("%s the %s joins you!" % [name, String(rec.class_name)], "important")
	_spawn(rec)
	_quest_hired()
	_saved()
	return true


## Bring a companion waiting at the inn back to your side (no fee).
func summon(id: int) -> void:
	var rec := by_id(id)
	if rec.is_empty() or String(info(rec).state) != "inn":
		return
	info(rec).state = "with"
	PlayerData.message.emit("%s joins you." % rec.name, "important")
	_spawn(rec)
	_saved()


## Back to the inn, with everything it carries.
func dismiss(id: int) -> void:
	var rec := by_id(id)
	if rec.is_empty() or String(info(rec).state) == "inn":
		return
	_despawn(id)
	info(rec).state = "inn" if String(info(rec).state) != "dead" else "dead"
	PlayerData.message.emit("%s heads back to the inn." % rec.name, "system")
	_saved()


## Sent away for good: whatever is still on it is lost; the slot takes a fresh level-5 hire again.
func release(id: int) -> void:
	var rec := by_id(id)
	if rec.is_empty():
		return
	_despawn(id)
	roster().erase(rec)
	PlayerData.message.emit("%s leaves your service for good." % rec.name, "system")
	_saved()


## What a healer asks to bring a fallen companion back (owner 2026-10-11): nothing below level 20, then what a player
## of its level pays a healer after one death - the constitution point it cost restored at the old server's price per
## point (rules con_restore_cost, GamePlayer.prcRestore; the level's squared x 50 copper before was too dear).
const FREE_REVIVE_BELOW := 20


static func revive_cost(rec: Dictionary) -> int:
	var l := int(rec.get("level", HIRE_LEVEL))
	if l < FREE_REVIVE_BELOW:
		return 0
	var table: Array = CombatRules.r().get("con_restore_cost", [1])
	return int(table[clampi(l, 0, table.size() - 1)])


func revive(id: int, healer: String) -> bool:
	var rec := by_id(id)
	if rec.is_empty() or String(info(rec).state) != "dead":
		return false
	var cost := revive_cost(rec)
	if PlayerData.total_copper() < cost:
		PlayerData.message.emit("%s says, \"Bringing %s back costs %s. You don't have that much.\"" % [healer, rec.name, PlayerData.money_string(cost)], "npc")
		return false
	PlayerData.set_copper(PlayerData.total_copper() - cost)
	_despawn(id)                                          # (the body, if it still lies in this zone)
	rec["hp"] = 999999                                    # whole again (clamped to its maximum when it loads)
	info(rec).state = "with"
	if cost > 0:
		PlayerData.message.emit("%s calls %s back from the dead. You give %s a donation of %s." % [healer, rec.name, healer, PlayerData.money_string(cost)], "system")
	else:
		PlayerData.message.emit("%s calls %s back from the dead." % [healer, rec.name], "system")
	_spawn(rec)
	_saved()
	return true


func with_you() -> Array:
	return roster().filter(func(r): return String(info(r).get("state", "")) == "with")


func dead() -> Array:
	return roster().filter(func(r): return String(info(r).get("state", "")) == "dead")


# --- in the world (GameBots runs them on the bots' simulation in the game) -------------------------------------

func _gamebots() -> Node:
	return WorldLink.bots


## Your zone loaded (ZoneViewer): the companions with you arrive beside you.
func zone_ready() -> void:
	_foes.clear()
	for r in with_you():
		_spawn(r)
	_group_rows()


func _spawn(rec: Dictionary) -> void:
	var gb := _gamebots()
	var p: Node3D = viewer.player
	if gb == null or p == null:
		if gb == null:
			PlayerData.message.emit("(Companions need the .NET build of the game - start it from the Offline DAoC Rebuilt launcher.)", "error")
		return
	var id := int(info(rec).id)
	if _foes.has(id):
		return
	if _temp.has(id):                                     # a window's sheet made from the record: written back, gone
		(_temp[id] as CharacterState).store_sheet()
		(_temp[id] as CharacterState).free()
		_temp.erase(id)
	var i := _foes.size()
	var back := Vector3(sin(p.facing()), 0, cos(p.facing()))     # behind you (the player faces -Z at yaw 0)
	var side := Vector3(back.z, 0, -back.x)
	var at := p.global_position + back * (2.5 + 1.5 * (i / 2)) + side * (1.8 if i % 2 == 0 else -1.8)
	at.y = p.global_position.y
	var foe = gb.call("AddCompanion", rec, at, rad_to_deg(p.facing()))
	if foe == null:
		return
	_foes[id] = foe
	var sheet: CharacterState = foe.get("sheet")
	sheet.is_companion = true
	sheet.message.connect(func(text: String, _k: String):
		if text.begins_with("You raise to level"):
			PlayerData.message.emit("%s has reached level %s!" % [rec.name, text.trim_prefix("You raise to level ").trim_suffix("!")], "important"))
	foe.set_meta("companion", id)
	foe.set("tactics", info(rec).get("tactics", []))
	foe.set("stance", String(info(rec).get("stance", "aggressive")))
	if String(info(rec).state) == "dead":                 # (lies dead where it fell)
		foe.set("alive", false)
	_group_rows()
	changed.emit()


func _despawn(id: int) -> void:
	var gb := _gamebots()
	if _foes.has(id):
		_store(id)
		_foes.erase(id)
	if gb:
		gb.call("RemoveCompanion", id)
	_group_rows()
	changed.emit()


func foe(id: int) -> Object:
	return _foes.get(id)


## A companion's sheet: the live one while it's in the world, else one made from its record (the windows edit it).
func sheet_of(rec: Dictionary) -> CharacterState:
	var f = _foes.get(int(info(rec).get("id", -1)))
	if f != null:
		return f.get("sheet")
	return null


func _store(id: int) -> void:
	var f = _foes.get(id)
	if f != null:
		f.call("record")


func store_all() -> void:
	for id in _foes:
		_store(id)


func _saved() -> void:
	store_all()
	PlayerData.save_character()
	changed.emit()


var _save_left := 20.0


func _process(delta: float) -> void:
	_save_left -= delta
	if _save_left <= 0.0:
		_save_left = 20.0
		if not _foes.is_empty():                          # their levels, experience and health kept (a crash loses little)
			store_all()
			PlayerData.save_character()
	_group_left -= delta
	if _group_left <= 0.0:
		_group_left = 0.5
		_watch_deaths()
		_group_rows()
	if _courier_left >= 0.0:
		_courier_left -= delta
		if _courier_left <= 0.0:
			_courier_left = -1.0
			_show_courier()


## A companion that died: "dead" on the roster (it stays where it fell until you leave the zone or a healer calls it).
func _watch_deaths() -> void:
	for id in _foes:
		var f = _foes[id]
		var rec := by_id(int(id))
		if rec.is_empty():
			continue
		var alive: bool = f.get("alive")
		if not alive and String(info(rec).state) == "with":
			info(rec).state = "dead"
			PlayerData.message.emit(("%s has died! Any healer of your realm can bring them back%s." % [rec.name,
					" for free" if revive_cost(rec) == 0 else ""]), "important")
			_saved()


## The group windows: your companions with you, their live health / power / endurance.
func _group_rows() -> void:
	var rows := []
	for r in with_you() + dead():
		var f = _foes.get(int(info(r).id))
		if f == null:
			continue
		var s: CharacterState = f.get("sheet")
		rows.append({"name": String(r.name), "class_name": String(r.get("class_name", "")), "level": s.level,
				"hp": float(s.hp) / maxf(1.0, s.max_hp), "hp_pts": s.hp,
				"power": float(s.power_pts) / maxf(1.0, s.max_power) if s.max_power > 0 else 0.0, "power_pts": s.power_pts,
				"end": float(s.end_pts) / float(CharacterState.MAX_END), "effects": [], "companion": int(info(r).id)})
	var before := PlayerData.group.map(func(m): return String(m.get("name", "")))
	PlayerData.group = rows
	if before != rows.map(func(m): return String(m.get("name", ""))):
		PlayerData.group_changed.emit()


# --- experience: a kill shared out across the group ----------------------------------------------------------

## A monster you or a companion killed, with companions at your side: the kill's experience - for the group's
## highest level, a group bonus for each member past the first - shared by level among the members within 2000 units
## (alive), each share no more than a kill of its own would give. Returns false when you have no companions with
## you (the solo rules stand). Improvised from the old server's group split - "1.65 EXCEPTIONS MADE.txt".
func group_xp(st: NpcState) -> bool:
	var members := []
	var p: Node3D = viewer.player
	if p and PlayerData.hp > 0 and p.global_position.distance_to(st.pos) <= GROUP_RANGE:
		members.append(["player", PlayerData.level])
	for id in _foes:
		var f = _foes[id]
		if f.get("alive") and (f.get("pos") as Vector3).distance_to(st.pos) <= GROUP_RANGE:
			members.append([f, int(f.call("level"))])
	if _foes.is_empty() or members.size() < 1:
		return false
	var top := 0
	var total_lv := 0
	for m in members:
		top = maxi(top, int(m[1]))
		total_lv += maxi(1, int(m[1]))
	var con := (viewer.npcs as NpcManager).con_level(top, st.level)
	var pool := float(CombatRules.kill_xp(st.level, top, con <= -3)) * (1.0 + SHARE_BONUS * (members.size() - 1))
	for m in members:
		var lv := maxi(1, int(m[1]))
		var own_con := (viewer.npcs as NpcManager).con_level(lv, st.level)
		var share := mini(int(pool * lv / total_lv), CombatRules.kill_xp(st.level, lv, own_con <= -3))
		if share <= 0:
			continue
		if m[0] is String:
			PlayerData.gain_xp(share)
		else:
			(m[0].get("sheet") as CharacterState).gain_xp(share)
	return true


# --- the level-5 courier and its quest -------------------------------------------------------------------------

func _inn() -> Dictionary:
	return inns.get(PlayerData.realm_key(), {})


func _zone_name(id: int) -> String:
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
	return String((idx as Dictionary).get(str(id), {}).get("name", "")) if idx is Dictionary else ""


## The quest the courier hands over, one per realm (registered with QuestDb each session; its state is on you).
func _register_quests() -> void:
	for realm in QUEST_ID:
		var inn: Dictionary = inns.get(realm, {})
		if inn.is_empty():
			continue
		var keeper := String(inn.innkeeper)
		var zone_name := _zone_name(int(inn.zone))
		var marker := {"zone": int(inn.zone), "pos": inn.door}
		QuestDb.add_runtime({"id": QUEST_ID[realm], "name": "Roadside Inn", "giver": _cap(String(inn.courier.name)),
				"min": HIRE_LEVEL, "max": 50, "classes": [], "races": [], "depends": [], "max_count": 1, "accept": "",
				"description": "", "final_rewards": [], "finish_text": "",
				"steps": [
					{"type": "interact", "target": keeper, "marker": marker, "step_item": "", "source_text": "", "target_text": "",
					 "text": "%s brought word of a roadside inn on the road near %s, in %s. Travel there and speak with %s, the innkeeper." % [_cap(String(inn.courier.name)), String(inn.town), zone_name, keeper]},
					{"type": "hire", "target": keeper, "marker": marker, "step_item": "", "source_text": "",
					 "target_text": "", "text": "%s can tell you about companions - adventurers who will travel and fight at your side. Hire your first companion from %s; the first one costs nothing." % [keeper, keeper]},
				]})


## Reached level 5 (or logged in at 5+) without the quest: it is yours now, whatever you're doing; the courier shows
## up for the look once you're alive and out of combat (or never, if that doesn't happen this session - the quest is
## already in your journal).
func _check_courier() -> void:
	if PlayerData.level < HIRE_LEVEL or _inn().is_empty():
		return
	var id := str(QUEST_ID.get(PlayerData.realm_key(), 0))
	if bool(PlayerData.character.get("companion_courier", false)) or PlayerData.quests.has(id) \
			or PlayerData.quests_done.has(id) or not roster().is_empty():
		return
	PlayerData.character["companion_courier"] = true
	PlayerData.quests[id] = {"step": 1}
	PlayerData.quests_changed.emit()
	PlayerData.save_character()
	PlayerData.message.emit("You have a new quest: Roadside Inn.", "important")
	_courier_left = 1.5


func _show_courier() -> void:
	var p: Node3D = viewer.player
	var cb: Combat = viewer.combat
	if p == null or PlayerData.hp <= 0 or (cb and cb.in_combat()):
		_courier_left = 3.0                               # later: alive and out of combat
		return
	if _courier and is_instance_valid(_courier):
		return
	var inn := _inn()
	var c := Courier.new()
	viewer.add_child(c)
	c.start(p, viewer.npcs, inn.courier, [
		"%s flutters up to you." % _cap(String(inn.courier.name)) if String(inn.courier.model) == "631" else
				("%s trots up to you with a message." % _cap(String(inn.courier.name)) if String(inn.courier.model) == "47" else
				"%s drifts up to you and glows softly." % _cap(String(inn.courier.name))),
		"\"Adventurer! %s, the innkeeper of the roadside inn near %s, asks for you. Travellers gather there - companions who would gladly fight at your side. Seek %s out.\"" % [String(inn.innkeeper), String(inn.town), String(inn.innkeeper)]])
	_courier = c


func _quest_hired() -> void:
	var id := str(QUEST_ID.get(PlayerData.realm_key(), 0))
	if not PlayerData.quests.has(id):
		return
	var q: QuestEngine = viewer.quests
	if q:
		PlayerData.quests[id].step = 2
		q.finish_scripted(id)


# --- managing one (CompanionWindow) -----------------------------------------------------------------------------

var window: CompanionWindow
var _temp := {}                                   # companion id -> a sheet made from its record (not in the world)


func manage(id: int) -> void:
	_drop_buff_tactics(id)
	if window:
		window.open_for(id, self)


## The sheet to show and change: the live one while it's with you, else one made from its record (written back on
## every change).
func edit_sheet(rec: Dictionary) -> CharacterState:
	var live := sheet_of(rec)
	if live:
		return live
	var id := int(info(rec).get("id", -1))
	if not _temp.has(id):
		var s := CharacterState.new()
		s.is_bot = true
		s.is_companion = true
		s.load_sheet(rec)
		s.recalc_max()
		_temp[id] = s
	return _temp[id]


func _after_change(id: int) -> void:
	var rec := by_id(id)
	var s := edit_sheet(rec)
	# the weapon set in hand must hold a weapon: else the first set that does (standard, two-handed, ranged)
	var slot_of := {"standard": 10, "twohand": 12, "ranged": 13}
	if s.item_at(int(slot_of.get(s.active_weapon, 10))).is_empty() and not (s.active_weapon == "standard" and not s.item_at(11).is_empty()):
		for k in ["standard", "twohand", "ranged"]:
			if not s.item_at(int(slot_of[k])).is_empty():
				s.active_weapon = k
				break
	s.recalc_max()
	s.store_sheet()
	var gb := _gamebots()
	if gb and _foes.has(id):
		gb.call("RedressCompanion", id)
	PlayerData.save_character()
	changed.emit()


## Hand an item from your backpack (or worn) to a companion's slot: its class must be able to use it there.
func give_item(id: int, player_slot: int, comp_slot: int) -> void:
	var rec := by_id(id)
	if rec.is_empty() or PlayerData.is_vault(player_slot):
		return
	var e := PlayerData.entry(player_slot)
	if e.is_empty():
		return
	var it := ItemDb.item(String(e.id))
	if int(it.get("isdropable", 1)) == 0:
		PlayerData.message.emit("You can't give the %s away." % it.get("name", "item"), "error")
		return
	var s := edit_sheet(rec)
	if s.is_equip_slot(comp_slot):
		if not s.can_hold(comp_slot, it):
			PlayerData.message.emit("The %s doesn't go there." % it.get("name", "item"), "error")
			return
		var why := s.use_problem(it)
		if why != "":
			PlayerData.message.emit("%s: %s" % [rec.name, why.replace("You ", "I ").replace("you ", "I ")], "error")
			return
	elif comp_slot < BAG_FIRST or comp_slot >= BAG_FIRST + BAG_SLOTS:
		return
	var back: Variant = s.inventory.get(comp_slot)
	var back_to := -1
	if back != null:                                      # what is there comes back to you: room first
		back_to = player_slot if PlayerData.is_backpack(player_slot) else PlayerData.first_free()
		if back_to < 0:
			PlayerData.message.emit("Your backpack is full.", "error")
			return
	PlayerData.inventory.erase(player_slot)
	s.inventory[comp_slot] = e
	if back != null:
		PlayerData.inventory[back_to] = back
	PlayerData.message.emit("You give the %s to %s." % [it.get("name", "item"), rec.name], "system")
	PlayerData.inventory_changed.emit()
	_after_change(id)


func _free_bag(s: CharacterState) -> int:
	for i in BAG_SLOTS:
		if not s.inventory.has(BAG_FIRST + i):
			return i
	return -1


## Take one of its items back into your backpack.
func take_item(id: int, comp_slot: int) -> void:
	var rec := by_id(id)
	var s := edit_sheet(rec)
	var e := s.entry(comp_slot)
	if e.is_empty():
		return
	var to := PlayerData.first_free()
	if to < 0:
		PlayerData.message.emit("Your backpack is full.", "error")
		return
	s.inventory.erase(comp_slot)
	PlayerData.inventory[to] = e
	PlayerData.message.emit("You take the %s from %s." % [ItemDb.item(String(e.id)).get("name", "item"), rec.name], "system")
	PlayerData.inventory_changed.emit()
	_after_change(id)


## Between its own slots (from its bag onto it, or off into the bag).
func move_item(id: int, from: int, to: int) -> void:
	var rec := by_id(id)
	var s := edit_sheet(rec)
	if from == to or s.entry(from).is_empty():
		return
	if not s.is_equip_slot(to) and (to < BAG_FIRST or to >= BAG_FIRST + BAG_SLOTS):
		return
	var it := ItemDb.item(String(s.entry(from).id))
	if s.is_equip_slot(to):
		if not s.can_hold(to, it):
			PlayerData.message.emit("The %s doesn't go there." % it.get("name", "item"), "error")
			return
		var why := s.use_problem(it)
		if why != "":
			PlayerData.message.emit("%s: %s" % [rec.name, why.replace("You ", "I ").replace("you ", "I ")], "error")
			return
	s.move(from, to)
	_after_change(id)


func train(id: int, key: String) -> void:
	var rec := by_id(id)
	var s := edit_sheet(rec)
	var lv := int(s.specs.get(key, 1))
	var name := String(ClassDb.spec(key).get("name", key))
	if lv >= s.level:
		PlayerData.message.emit("%s can't train %s any higher until reaching another level." % [rec.name, name], "error")
		return
	if s.spec_points() < lv + 1:
		PlayerData.message.emit("%s hasn't enough specialization points to train %s." % [rec.name, name], "error")
		return
	if s.train(key):
		PlayerData.message.emit("%s trains %s to %d." % [rec.name, name, int(s.specs[key])], "system")
		_after_change(id)


func set_stance(id: int, stance: String) -> void:
	var rec := by_id(id)
	info(rec).stance = stance
	var f = _foes.get(id)
	if f != null:
		f.set("stance", stance)
	PlayerData.message.emit("%s takes %s %s stance." % [rec.name, "an" if stance[0] in "aeiou" else "a", stance], "system")
	_saved()


func set_upkeep(id: int, on: bool) -> void:
	info(by_id(id)).upkeep = on
	_saved()


func _push_tactics(id: int) -> void:
	var f = _foes.get(id)
	if f != null:
		f.set("tactics", info(by_id(id)).get("tactics", []))
	_saved()


## A buff spell (owner 2026-10-11): cast automatically when needed - never on the 10-slot bar, which holds attacks, pet
## summons, styles and heals. A friendly spell that isn't a heal, cure or summon.
const HEAL_TYPES := ["Heal", "SpreadHeal", "OmniHeal", "HealOverTime", "CombatHeal", "SavageEnduranceHeal"]


static func is_buff(spell: Dictionary) -> bool:
	if spell.is_empty():
		return false
	var t := String(spell.get("target", "")).to_lower()
	var kind := String(spell.get("type", ""))
	if not (t in ["self", "realm", "group"]):
		return false
	if kind in HEAL_TYPES or kind.begins_with("Cure") or kind.begins_with("Summon") or kind.begins_with("Resurrect"):
		return false
	return true


## Buffs taken off a companion's bar (from before they were automatic).
func _drop_buff_tactics(id: int) -> void:
	var rec := by_id(id)
	if rec.is_empty():
		return
	var tac: Array = info(rec).get("tactics", [])
	var keep := tac.filter(func(t): return not (String(t.get("kind", "")) == "spell" and is_buff(ClassDb.spell(int(t.get("id", 0))))))
	if keep.size() != tac.size():
		info(rec).tactics = keep
		_push_tactics(id)


func add_tactic(id: int, entry: Dictionary) -> void:
	var tac: Array = info(by_id(id)).get("tactics", [])
	if tac.size() >= 10:
		return
	if String(entry.get("kind", "")) == "spell" and is_buff(ClassDb.spell(int(entry.get("id", 0)))):
		return                                             # (buffs are automatic)
	tac.append({"kind": String(entry.kind), "id": int(entry.id), "name": String(entry.name), "attack": bool(entry.get("attack", entry.kind == "style"))})
	info(by_id(id)).tactics = tac
	_push_tactics(id)


func remove_tactic(id: int, i: int) -> void:
	var tac: Array = info(by_id(id)).get("tactics", [])
	if i >= 0 and i < tac.size():
		tac.remove_at(i)
	_push_tactics(id)


## Move bar slot i up (-1) or down (+1); returns where it went.
func move_tactic(id: int, i: int, d: int) -> int:
	var tac: Array = info(by_id(id)).get("tactics", [])
	var j := i + d
	if i < 0 or i >= tac.size() or j < 0 or j >= tac.size():
		return i
	var t = tac[i]
	tac[i] = tac[j]
	tac[j] = t
	_push_tactics(id)
	return j


func _exit_tree() -> void:
	store_all()
	for id in _temp:
		(_temp[id] as CharacterState).store_sheet()
		(_temp[id] as CharacterState).free()
	_temp.clear()


## "a messenger fairy" -> "A messenger fairy" (only the first letter: the old server's way with lower-case names).
static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t
