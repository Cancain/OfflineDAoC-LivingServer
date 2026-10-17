class_name TaskSystem
extends Node
## The 1.65 task system (owner 2026-10-10; rules and sources in pipeline/build_tasks.py, data content/quests/tasks.json):
##   /task (or /say task, /say help) with an NPC targeted asks it for a task; /task with nothing targeted (or yourself)
##   shows your task; /task abort gives it up. Separate from the journal's QUEST GUIDE button (the old client sent
##   /task from that button; this one has no such limit).
##   Kill tasks: from any named guard whose zone has a valid target for you (owner 2026-10-10) - a common monster
##   of level L-2 .. L there; he names it and its direction; kill one, then right-click the same guard.
##   Delivery tasks: from any other NPC of your realm, 35% of the time (else it has nothing for 5 minutes): an item
##   for an NPC elsewhere in the zone; hand it over (drag it onto them).
##   Levels 1-19 only; tasks per level = your level (they start over at each level); two hours to finish; dying,
##   running out of time or giving it up fails it, and a failed task still counts.
##   QOL (1.65 EXCEPTIONS MADE.txt): the target is marked in the task's own colour (QuestMarkers "task") on the ground
##   and on the map, where the original only named a direction.

const SAVE := "task"                          # the active task (PlayerData.character)
const DONE := "tasks_done"                    # {level, count}: tasks done or failed at that level
const ITEM_ID := "task_delivery_item"
const DATA := "res://content/quests/tasks.json"
const NO_TASK := "I have no tasks for you at the moment. Come back sometime later, perhaps then you can help me with something."

static var _data := {}
var viewer: Node
var _pause_until := 0.0                       # unix time: a refusal makes NPCs wait 5 minutes (task_pause_ticks)
var _tick := 0.0


static func data() -> Dictionary:
	if _data.is_empty():
		var p = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
		_data = p if p is Dictionary else {"max_level": 19, "kill_guards": {}}
	return _data


static func current() -> Dictionary:
	var t = PlayerData.character.get(SAVE, {})
	return t if t is Dictionary else {}


func setup(v: Node) -> void:
	viewer = v
	PlayerData.said.connect(_on_said)
	_restore_item()


# --- asking -------------------------------------------------------------------------------------------------------

## The chat command: "/task", "/task status", "/task abort".
func command(args: String) -> void:
	var a := args.strip_edges().to_lower()
	if a == "abort":
		var t := current()
		if not t.is_empty():
			_fail(t, "Your %s has expired!" % String(t.name))
		return
	var n: Npc = viewer.npcs.target if viewer.npcs else null
	if a == "status" or n == null:
		_status()
		return
	ask(n)


func _on_said(text: String) -> void:
	var w := text.strip_edges().to_lower().trim_suffix(".").trim_suffix("!").trim_suffix("?")
	var n: Npc = viewer.npcs.target if viewer.npcs else null
	if (w == "task" or w == "help") and n and int(n.spawn.realm) != 0:
		ask(n)


func ask(n: Npc) -> void:
	if n.global_position.distance_to(viewer.player.global_position) > 12.0:
		PlayerData.message.emit("%s is too far away to interact" % _cap(n.display_name(true)), "system")
		return
	if int(n.spawn.realm) == 0 or int(n.spawn.realm) != PlayerData.realm_id():
		return
	_check_expired()
	var lv := PlayerData.level
	if lv > int(data().max_level):
		PlayerData.message.emit("Tasks are only available to players up to level %d!" % int(data().max_level), "system")
		return
	if not current().is_empty():
		PlayerData.message.emit("You already have a Task. Select yourself and type /Task for more Information.", "system")
		return
	if done_this_level() >= lv:
		PlayerData.message.emit("You cannot do more than %d tasks at your level!" % lv, "system")
		return
	if Time.get_unix_time_from_system() < _pause_until:
		_say(n, NO_TASK)
		return
	if named_guard(n.spawn):
		_build_kill(n)                                      # no monster of your level in his zone: he says so
		return
	if str(n.spawn.get("role", "")) == "guard":
		return
	if randf() * 100.0 < float(data().get("delivery_chance", 35)):
		_build_delivery(n)
	else:
		_say(n, NO_TASK)
		_pause_until = Time.get_unix_time_from_system() + float(data().get("pause_s", 300))


## KillTask.CheckNamedGuard (old server): a realm NPC named like a guard with a name of its own.
static func named_guard(s: Dictionary) -> bool:
	if int(s.get("realm", 0)) == 0:
		return false
	var n := String(s.get("name", ""))
	var g := String(s.get("guild", ""))
	if n.contains("Guard"):
		if n in ["Guardian", "Guardian Sergeant", "Guard", "Guard's Armorer", "Guards' Armorer", "Guardsman"] \
				or n.ends_with("Guardian") or n.ends_with("Guard") or n.ends_with("Guardsman") or n.begins_with("Guardian of the"):
			return false
		return true
	for p in ["Sir ", "Captain ", "Lady "]:
		if n.begins_with(p) and g == "":
			return true
	for p in ["Jarl ", "Soldier ", "Soldat ", "Huntress ", "Bork "]:
		if n.begins_with(p):
			return true
	if n.begins_with("Sentinel "):
		return not (n.ends_with("Runes") or n.ends_with("Kynon"))
	if n.contains("Viking"):
		return not (n.ends_with("Archer") or n.ends_with("Dreng") or n.ends_with("Huscarl") or n.ends_with("Jarl"))
	return n.contains("Flayer") and n.ends_with("Kegnar")


func _build_kill(n: Npc) -> void:
	var lv := PlayerData.level
	var pool := []
	for s in viewer.npcs.states:                          # KillTask.GetRandomMob: the zone's level L-2 .. L monsters
		var st: NpcState = s
		if st.zone_id >= 0 and st.zone_id != int(viewer.zone.info.id):
			continue                                       # (seamless zones: a neighbour's spawns are not this zone's)
		var nm := String(st.spawn.name)
		if int(st.spawn.realm) == 0 and nm != "" and nm == nm.to_lower() and int(st.spawn.level) >= lv - 2 and int(st.spawn.level) <= lv:
			pool.append(st)
	if pool.is_empty():
		_say(n, "Sorry, I couldn't find any mob kill order. Come back later!")
		return
	var mob: NpcState = pool[randi() % pool.size()]
	var dir := direction(n.global_position, mob.pos)
	var t := {"type": "kill", "name": "Kill Task", "giver": String(n.spawn.name), "mob": String(mob.spawn.name),
			"target_zone": int(viewer.zone.info.id), "target_pos": [mob.pos.x, mob.pos.y, mob.pos.z], "dir": dir,
			"killed": false, "expires": Time.get_unix_time_from_system() + float(data().get("expire_s", 7200))}
	_store(t)
	PlayerData.message.emit("%s says, *Very well %s, it's good to see adventurers willing to help out the realm in such times. Search to the %s and kill a %s and return to me for your reward. Good luck!*" % [
			String(n.spawn.name), PlayerData.display_name(), dir, String(mob.spawn.name)], "npc")


func _build_delivery(n: Npc) -> void:
	var pool := []
	var far := []
	for s in viewer.npcs.states:                          # MoneyTask.GetRandomNPC: a realm NPC of the zone
		var st: NpcState = s
		if st.zone_id >= 0 and st.zone_id != int(viewer.zone.info.id):
			continue
		if int(st.spawn.realm) != PlayerData.realm_id() or String(st.spawn.name) == "" or st.spawn == n.spawn:
			continue
		if String(st.spawn.name) == String(n.spawn.name) or named_guard(st.spawn) or str(st.spawn.get("role", "")) == "guard":
			continue
		var nm := String(st.spawn.name)                   # a person with a name: not "ambient pixie", not untargetable
		if nm.left(1) != nm.left(1).to_upper() or int(st.spawn.get("flags", 0)) & (Npc.FLAG_CANTTARGET | Npc.FLAG_DONTSHOWNAME):
			continue
		pool.append(st)
		if st.pos.distance_to(n.global_position) > 200.0:    # period: "an item ... to another NPC in another town"
			far.append(st)
	if pool.is_empty():
		_say(n, "I have no task for you, come back some time later.")
		return
	var to: NpcState = (far if not far.is_empty() else pool)[randi() % (far if not far.is_empty() else pool).size()]
	var d: Dictionary = data().get("delivery_items", {})
	var k := randi() % (d.objects as Array).size()
	var item_name := String((d.formats as Array)[randi() % (d.formats as Array).size()]).format(
			[String(to.spawn.name), String((d.sizes as Array)[randi() % (d.sizes as Array).size()]), String(d.objects[k])])
	var model := int(d.models[k])
	var item := {"id": ITEM_ID, "name": item_name, "level": PlayerData.level, "model": model,
			"icon": int((d.get("icons", {}) as Dictionary).get(str(model), 0)), "object_type": 0, "item_type": 1, "weight": 1,
			"quality": 80 + PlayerData.level, "condition": 90, "maxcondition": 90, "durability": 1000, "maxdurability": 1000,
			"price": 0, "isdropable": 1, "istradable": 0, "maxcount": 1, "packsize": 1}
	var zone_name := String(viewer.zone.info.get("name", ""))
	var t := {"type": "delivery", "name": "Money Task", "giver": String(n.spawn.name), "receiver": String(to.spawn.name),
			"receiver_zone": zone_name, "target_zone": int(viewer.zone.info.id),
			"target_pos": [to.pos.x, to.pos.y, to.pos.z], "item": item,
			"expires": Time.get_unix_time_from_system() + float(data().get("expire_s", 7200))}
	ItemDb.add_runtime(ITEM_ID, item)
	if not PlayerData.give_item(ITEM_ID, String(n.spawn.name)):
		return                                             # backpack full: no task
	_store(t)
	_say(n, "Bring %s to %s in %s" % [item_name, String(to.spawn.name), zone_name])


# --- doing it -----------------------------------------------------------------------------------------------------

## A monster you killed: the kill task's target (any monster of that name).
func on_kill(st: NpcState) -> void:
	var t := current()
	if String(t.get("type", "")) != "kill" or bool(t.get("killed", false)) or _check_expired():
		return
	if String(st.spawn.name).to_lower() == String(t.mob).to_lower():
		t["killed"] = true
		_store(t)
		PlayerData.message.emit("You must now return to %s to receive your reward!" % String(t.giver), "system")


## Right-click: the kill task's guard pays out. True when the task handled it.
func on_interact(n: Npc) -> bool:
	var t := current()
	if String(t.get("type", "")) != "kill" or not bool(t.get("killed", false)) or _check_expired():
		return false
	if String(n.spawn.name) != String(t.giver):
		return false
	PlayerData.message.emit("%s says, *Good work %s. Here is your reward as promised.*" % [String(n.spawn.name), PlayerData.display_name()], "npc")
	_finish(t)
	return true


## An item handed to an NPC: the delivery task's item to its receiver. True when the task took it.
func on_give(n: Npc, slot: int) -> bool:
	var t := current()
	if String(t.get("type", "")) != "delivery" or String(PlayerData.entry(slot).get("id", "")) != ITEM_ID:
		return false
	if _check_expired() or String(n.spawn.name) != String(t.receiver):
		return false
	PlayerData.take_one(slot)
	_finish(t)
	return true


## You died: the task fails (period: "You can fail a task ... if the timer runs out or you die").
func on_player_died(_killer: String) -> void:
	var t := current()
	if not t.is_empty():
		_fail(t, "Your %s has failed!" % String(t.name))


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 5.0
		_check_expired()


## AbstractTask.CheckTaskExpired: out of time, or past the task levels.
func _check_expired() -> bool:
	var t := current()
	if t.is_empty():
		return false
	if Time.get_unix_time_from_system() > float(t.get("expires", 0)) or PlayerData.level > int(data().max_level):
		_fail(t, "Your %s has expired!" % String(t.name))
		return true
	return false


# --- the end ------------------------------------------------------------------------------------------------------

## The reward (owner 2026-10-10: the period guide first, the old server only where it says nothing):
##   a kill task: "about triple a yellow kill experience" (period guide) - 3 x a same-level monster's kill;
##   a delivery task: the guide gives no number, only "not as rewarding as kill tasks" - the old server's
##   (AbstractTask.RewardXP: total experience of the level / 2 / (level - 1)), never more than a kill task's;
##   money: the old server's tables for the task's kind (+-3%), the guide gives no amounts.
## Worked out when you claim it (period tip: claim after levelling and it pays at the new level).
static func reward_xp(kind: String, lv: int) -> int:
	var kill := 3 * CombatRules.kill_xp(lv, lv, false)
	if kind == "kill":
		return kill
	var old := int(CombatRules.xp_for_level(lv) * 0.5 / (lv - 1)) if lv > 1 else 0
	return mini(old, kill)


func _finish(t: Dictionary) -> void:
	var lv := PlayerData.level
	var xp := reward_xp(String(t.type), lv)
	var table: Array = data().get("kill_money" if String(t.type) == "kill" else "delivery_money", [])
	var base := int(table[clampi(lv - 1, 0, table.size() - 1)]) if not table.is_empty() else 0
	var spread := (base / 100) * 3
	var money := randi_range(base - spread, base + spread)
	if xp > 0:
		PlayerData.gain_xp(xp, false)
	if money > 0:
		PlayerData.set_copper(PlayerData.total_copper() + money)
		PlayerData.message.emit("You receive %s for completing your task." % PlayerData.money_string(money), "system")
	PlayerData.message.emit("You finish the %s!" % String(t.name), "system")
	_count_done()
	_clear()


func _fail(t: Dictionary, why: String) -> void:
	if String(t.get("type", "")) == "delivery":
		var s := PlayerData.find_item(ITEM_ID)
		if s >= 0:
			PlayerData.take_one(s)
			PlayerData.message.emit("Your task related item has been removed from your inventory.", "system")
	PlayerData.message.emit(why, "system")
	_count_done()                                          # period: a failed task still counts for the level
	_clear()


func done_this_level() -> int:
	var d = PlayerData.character.get(DONE, {})
	return int(d.get("count", 0)) if d is Dictionary and int(d.get("level", -1)) == PlayerData.level else 0


func _count_done() -> void:
	PlayerData.character[DONE] = {"level": PlayerData.level, "count": done_this_level() + 1}


func _store(t: Dictionary) -> void:
	PlayerData.character[SAVE] = t
	PlayerData.save_character()
	PlayerData.quests_changed.emit()                       # journal + markers


func _clear() -> void:
	PlayerData.character.erase(SAVE)
	PlayerData.save_character()
	PlayerData.quests_changed.emit()


func _restore_item() -> void:                              # a saved delivery item's description, back after a load
	var t := current()
	if String(t.get("type", "")) == "delivery" and t.get("item") is Dictionary:
		ItemDb.add_runtime(ITEM_ID, t.item)


## /task with nothing targeted (the old server's snapshot).
func _status() -> void:
	_check_expired()
	var t := current()
	if not t.is_empty():
		var ends := Time.get_datetime_dict_from_unix_time(int(t.expires) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
		var lines := ["You are on %s" % String(t.name), "What to do: %s" % describe(t), "",
				"Task will expire at %02d:%02d" % [int(ends.hour), int(ends.minute)],
				"You have done %d tasks out of %d at this level." % [done_this_level(), PlayerData.level]]
		if viewer.ui and viewer.ui.has_method("show_lines"):
			viewer.ui.show_lines("TASKS (SNAPSHOT)", lines)
		else:
			for l in lines:
				PlayerData.message.emit(l, "system")
	elif PlayerData.level <= int(data().max_level) and done_this_level() >= PlayerData.level:
		PlayerData.message.emit("You can do no more tasks at your current level", "system")
	else:
		PlayerData.message.emit("You have currently no pending task", "system")


static func describe(t: Dictionary) -> String:
	if String(t.get("type", "")) == "kill":
		return ("Find a %s and kill it then return to %s for your reward." % [String(t.mob), String(t.giver)]) \
				if not bool(t.get("killed", false)) else "Return to %s for your reward!" % String(t.giver)
	return "Bring the %s to %s in %s" % [String(t.get("item", {}).get("name", "item")), String(t.receiver), String(t.receiver_zone)]


## The compass word for the way from a guard to a spot (engine x = east, z = south).
static func direction(from: Vector3, to: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(to.x - from.x, -(to.z - from.z))), 360.0)   # 0 = north, clockwise
	return ["North", "North East", "East", "South East", "South", "South West", "West", "North West"][int(roundf(a / 45.0)) % 8]


func _say(n: Npc, text: String) -> void:
	if viewer.ui and viewer.ui.npc_dialog:
		viewer.ui.npc_dialog.say(String(n.spawn.id), String(n.spawn.name), text)
	else:
		PlayerData.message.emit("%s says, \"%s\"" % [String(n.spawn.name), text], "npc")


static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)
