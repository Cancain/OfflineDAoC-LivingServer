class_name Emissaries
extends Node
## The three faction emissaries - the ONLY custom (non-1.65) NPCs, owner 2026-10-09. The old project's own design
## (FactionEmissaryRuntime / FactionReputationQuest / FactionReputationTargets; rules + words in
## content/quests/emissaries.json from pipeline/build_emissaries.py), rebuilt here:
##   - talk (your realm's emissary, within 600 units): no hunt -> greeting with [hunt] / [how]; hunting -> progress
##     with [show location] / [reroll]; done -> [Claim reward];
##   - [hunt]: an accept dialog; the hunt is 10 of one common enemy species of the faction at the level nearest yours
##     without going over (cap 45) plus up to 3 below; any of that name in the faction's lands (outdoors) counts;
##   - [reroll] (confirm): another species, the hunt then grants only +5 until turned in;
##   - [Claim reward]: faction aggro -10 (-5 rerolled); the hunted species' own faction +the same if its base is
##     above 75 and the two are enemies. Repeatable. The red dot marks the hunting ground on that zone's map.
## Faction stable masters that refuse you (GameNPC.Interact's "dirty look") also point you to the emissary.

const SAVE_KEY := "emissary_hunt"
static var _data := {}
var viewer: Node


static func data() -> Dictionary:
	if _data.is_empty():
		var p = JSON.parse_string(FileAccess.get_file_as_string("res://content/quests/emissaries.json")) \
				if FileAccess.file_exists("res://content/quests/emissaries.json") else null
		_data = p if p is Dictionary else {"emissaries": {}}
	return _data


static func mine() -> Dictionary:
	return (data().get("emissaries", {}) as Dictionary).get(str(PlayerData.realm_id()), {})


static func hunt() -> Dictionary:
	var h = PlayerData.character.get(SAVE_KEY, {})
	return h if h is Dictionary else {}


static func is_ready() -> bool:
	var h := hunt()
	return not h.is_empty() and int(h.get("progress", 0)) >= int(h.get("required", 10))


static func gain() -> int:
	return int(data().get("rerolled_gain", 5)) if bool(hunt().get("rerolled", false)) else int(data().get("full_gain", 10))


## Reputation shown as trust: the negative of the faction's aggro, with its standing.
static func standing_text(fid: int) -> String:
	var a := PlayerData.faction_aggro(fid)
	return "%d/100 (%s)" % [-clampi(a, -100, 100), PlayerData.faction_standing(fid).capitalize()]


func setup(v: Node) -> void:
	viewer = v


func _e_say(n: Npc, text: String) -> void:
	viewer.ui.npc_dialog.say(String(n.spawn.id), String(n.spawn.name), text)


func _near(n: Npc) -> bool:
	return n.global_position.distance_to(viewer.player.global_position) <= float(data().get("talk_range_units", 600)) * 0.025


func _fill(t: String, e: Dictionary) -> String:
	var h := hunt()
	var fid := int(e.faction)
	var st := "Your reputation: %s. " % standing_text(fid)
	st += "That is enough for the trusted stable masters." if PlayerData.faction_aggro(fid) <= int(data().get("stable_trust", 50)) \
			else "The trusted stable masters need -%d or better." % int(data().get("stable_trust", 50))
	var half := " This hunt grants +%d." % int(data().get("rerolled_gain", 5)) if bool(h.get("rerolled", false)) else ""
	return t.replace("{gated}", String(e.text.gated)).replace("{standing}", st).replace("{target}", String(h.get("target", ""))) \
			.replace("{hunt}", "%s in %s: %d/%d" % [h.get("target", ""), h.get("zone_name", ""), int(h.get("progress", 0)), int(h.get("required", 10))]) \
			.replace("{half}", half)


## A right-click on an NPC. True when it was an emissary (it spoke).
func on_interact(n: Npc) -> bool:
	if String(n.spawn.get("role", "")) != "emissary":
		return false
	var e := mine()
	if e.is_empty() or String(e.name) != String(n.spawn.name) or not _near(n):
		return true                                          # another realm's emissary: no words for you
	if hunt().is_empty():
		_e_say(n, _fill(String(e.text.greeting), e))
	elif is_ready():
		_e_say(n, _fill(String(e.text.ready), e))
	else:
		_e_say(n, _fill(String(e.text.progress), e))
	return true


## A clicked / whispered keyword at an emissary. True when it was one.
func on_keyword(n: Npc, word: String) -> bool:
	if String(n.spawn.get("role", "")) != "emissary":
		return false
	var e := mine()
	if e.is_empty() or String(e.name) != String(n.spawn.name) or not _near(n):
		return true
	var w := word.strip_edges().to_lower()
	if w in e.text.hunt_words:
		if hunt().is_empty() and PlayerData.level >= 1 and PlayerData.level <= 50:
			_offer(n, e)
	elif w in e.text.how_words:
		_e_say(n, String(e.text.how))
	elif w == "show location":
		var h := hunt()
		if not h.is_empty():
			_e_say(n, "Seek %s in %s. Enter that zone and open its map to see the red dot. Any %s in the %s lands counts." % [h.target, h.zone_name, h.target, e.faction_name])
	elif w == "reroll":
		if not hunt().is_empty():
			_confirm("Choose different prey? This hunt will then grant only +%d reputation, even after further rerolls." % int(data().get("rerolled_gain", 5)),
					"YES", "NO", func():
						if _near(n):
							_assign(e, true, String(hunt().get("target", ""))))
	elif w == "claim reward" or w == "reward":
		if is_ready():
			_claim(n, e)
	return true


func _offer(n: Npc, e: Dictionary) -> void:
	_confirm("Hunt ten enemies of the %s near your strength? Return to %s for +%d %s reputation. The red dot marks the hunting ground on that zone's map." % [e.faction_name, e.name, int(data().get("full_gain", 10)), e.faction_name],
			"ACCEPT", "DECLINE", func():
				if _near(n) and hunt().is_empty() and not _assign(e, false, ""):
					PlayerData.message.emit("No hunt could be chosen right now. Please speak to the emissary again.", "system"))


func _confirm(text: String, yes: String, no: String, on_yes: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = text.to_upper()
	d.ok_button_text = yes
	d.cancel_button_text = no
	d.confirmed.connect(on_yes)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	viewer.ui.add_child(d)
	d.popup_centered()


## FactionReputationTargets.SelectPool: species with 5+ spawns first; the level nearest yours without going over
## (cap 45) and anything up to 3 below; a player below every target gets the lowest ones; a reroll skips the last one.
static func pool(e: Dictionary, level: int, excluded: String) -> Array:
	var allowed: Array = (e.get("candidates", []) as Array).filter(func(c): return excluded == "" or String(c.name).to_lower() != excluded.to_lower())
	var common := allowed.filter(func(c): return int(c.spawns) >= int(data().get("min_spawns", 5)))
	if not common.is_empty():
		allowed = common
	if allowed.is_empty():
		return []
	var cap := mini(maxi(level, 1), int(data().get("level_cap", 45)))
	var win := int(data().get("level_window", 3))
	var below := allowed.filter(func(c): return int(c.level) <= cap)
	if not below.is_empty():
		var best := 0
		for c in below:
			best = maxi(best, int(c.level))
		return below.filter(func(c): return int(c.level) >= best - win)
	var lowest := 999
	for c in allowed:
		lowest = mini(lowest, int(c.level))
	return allowed.filter(func(c): return int(c.level) <= lowest + win)


func _assign(e: Dictionary, rerolled: bool, previous: String) -> bool:
	var p := pool(e, PlayerData.level, previous)
	if p.is_empty():
		if rerolled:
			PlayerData.message.emit("No different hunt is available right now. Your hunt and reward are unchanged.", "system")
		return false
	var c: Dictionary = p[randi() % p.size()]
	var reduced := rerolled or bool(hunt().get("rerolled", false))
	PlayerData.character[SAVE_KEY] = {"target": c.name, "faction": int(c.faction), "zone": int(c.zone), "zone_name": c.zone_name,
			"pos": c.pos, "level": int(c.level), "required": int(data().get("required", 10)), "progress": 0, "rerolled": reduced,
			"hunt_zones": e.hunt_zones}
	PlayerData.save_character()
	if rerolled:
		PlayerData.message.emit("New hunt: %d %s in %s. This hunt now grants +%d reputation." % [int(data().get("required", 10)), c.name, c.zone_name, int(data().get("rerolled_gain", 5))], "system")
	else:
		PlayerData.message.emit("New hunt: %d %s in %s. The red dot marks them on that zone's map." % [int(data().get("required", 10)), c.name, c.zone_name], "system")
	PlayerData.quests_changed.emit()
	return true


## A monster you killed: any of the hunted name, no realm, in the faction's outdoor lands.
func on_kill(st: NpcState) -> void:
	var h := hunt()
	if h.is_empty() or is_ready() or int(st.spawn.get("realm", 0)) != 0:
		return
	if String(st.spawn.name).to_lower() != String(h.target).to_lower():
		return
	if not (int(viewer.zone.info.id) in (h.get("hunt_zones", []) as Array).map(func(z): return int(z))):
		return
	h.progress = int(h.progress) + 1
	PlayerData.character[SAVE_KEY] = h
	PlayerData.save_character()
	if is_ready():
		PlayerData.message.emit("Hunt complete. Return to the emissary to claim your reputation.", "system")
	PlayerData.quests_changed.emit()


func _claim(n: Npc, e: Dictionary) -> void:
	var g := gain()
	var fid := int(e.faction)
	var factions: Dictionary = CombatRules.r().get("factions", {})
	PlayerData.factions[str(fid)] = clampi(PlayerData.faction_aggro(fid) - g, -100, 100)
	var h := hunt()
	var enemy := int(h.get("faction", 0))
	var note := ""
	var ef: Dictionary = factions.get(str(enemy), {})
	var mf: Dictionary = factions.get(str(fid), {})
	# ShouldPenalizeEnemy: another faction, hostile by default (base above 75), and the two are enemies
	if enemy != fid and not ef.is_empty() and int(ef.get("base", 0)) > 75 and \
			(enemy in (mf.get("enemies", []) as Array).map(func(x): return int(x)) or fid in (ef.get("enemies", []) as Array).map(func(x): return int(x))):
		PlayerData.factions[str(enemy)] = clampi(PlayerData.faction_aggro(enemy) + g, -100, 100)
		note = " The %s will remember this." % String(ef.get("name", ""))
	PlayerData.character.erase(SAVE_KEY)
	PlayerData.save_character()
	_e_say(n, String(e.text.paid))
	PlayerData.message.emit("%s reputation +%d: now %s.%s" % [e.faction_name, g, standing_text(fid), note], "system")
	PlayerData.quests_changed.emit()


## A faction stable master that gave you a dirty look: who to see about it (FactionEmissaryRuntime.TryGetStableRefusal).
static func stable_refusal(n: Npc) -> String:
	var fid := int(n.spawn.get("faction", 0))
	var all: Dictionary = data().get("emissaries", {})
	var e: Dictionary = {}
	for k in all:
		if int(all[k].faction) == fid:
			e = all[k]
	var fname := String((CombatRules.r().get("factions", {}) as Dictionary).get(str(fid), {}).get("name", ""))
	if e.is_empty() or str(PlayerData.realm_id()) != _realm_of(e):
		return "%s will not deal with you. The %s do not trust you (%s)." % [n.spawn.name, fname, standing_text(fid)]
	var beside := ("right here beside %s" % e.host) if String(n.spawn.name).to_lower() == String(e.host).to_lower() \
			else "beside %s in %s" % [e.host, e.town]
	return "%s The %s do not trust you yet: reputation %s. The %s need -%d or better. Speak with %s, the %s Emissary, %s." % [
			String(e.text.refusal).replace("{master}", String(n.spawn.name)), fname, standing_text(fid), e.mounts,
			int(data().get("stable_trust", 50)), e.name, e.faction_name, beside]


static func _realm_of(e: Dictionary) -> String:
	var all: Dictionary = data().get("emissaries", {})
	for k in all:
		if all[k] == e:
			return String(k)
	return ""


## The journal's line for the hunt (FactionReputationQuest.FormatJournalDescription).
static func journal_text() -> String:
	var h := hunt()
	var e := mine()
	if h.is_empty():
		return ""
	var action := ("%d/%d %s slain. Return to the emissary." % [int(h.progress), int(h.required), h.target]) if is_ready() \
			else "Slay %s: %d/%d." % [h.target, int(h.progress), int(h.required)]
	return "%s In %s; the red dot marks them on that zone's map. Reward: +%d %s reputation." % [action, h.zone_name, gain(), e.get("faction_name", "faction")]
