extends Node
## Debug: tries to complete every quest of the zone through QuestEngine, doing each step the way a player would
## (the right class / race / level, the giver's accept keyword, then: kill the target, interact / whisper to it, hand it
## the item, search the area, use the item at the place ...) and reports which quests finish and where the others
## stop. Items a step needs that nothing in the zone hands out are given (and counted) so later steps still get tested.
##   --skip-login --zone=200 --figure=cel_m --ui-test --probe=quest_runner [--quest=<id>]
var viewer: Node
var eng: QuestEngine
var log_lines := []


func _process(_delta: float) -> void:
	if PlayerData.hp > 0 and PlayerData.hp < PlayerData.max_hp:
		PlayerData.set_hp(PlayerData.max_hp)


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	eng = viewer.quests
	# the runner checks quest data, not fights: monsters don't notice its character (as a shade) and it stays whole
	viewer.player.shade = true
	set_process(true)
	if viewer.args.has("quest"):                            # one quest: show its chat
		PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var zid := int(viewer.zone.info.id)
	var ids := []
	for id in QuestDb.all():
		if int(QuestDb.quest(id).get("zone", 0)) == zid and (not viewer.args.has("quest") or String(viewer.args.quest) == String(id)):
			ids.append(String(id))
	ids.sort()
	var done := 0
	var stuck := {}
	var given := 0
	for id in ids:
		var r: Array = await _run(id)
		given += int(r[1])
		if r[0] == "done":
			done += 1
		else:
			stuck[r[0]] = int(stuck.get(r[0], 0)) + 1
	print("[runner] zone %d: %d / %d quests completed, %d items had to be given, %d cross-zone stand-ins; stuck: %s" % [zid, done, ids.size(), given, cross_zone, stuck])
	var f := FileAccess.open(String(viewer.args.get("out", "user://")) + "/quest_runner_%d.txt" % zid, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
	get_tree().quit()


func _run(id: String) -> Array:
	var q := QuestDb.quest(id)
	PlayerData.quests = {}
	PlayerData.quests_done = {}
	for d in q.get("depends", []):                         # its prerequisite quests count as done (not itself:
		for other in QuestDb.all():                        # chains reuse one name for their parts)
			if String(other) != id and String(QuestDb.quest(other).name).to_lower() == String(d).to_lower():
				PlayerData.quests_done[String(other)] = 1
	PlayerData.level = clampi(int(q.min), 1, 50)
	var classes: Array = q.get("classes", [])
	PlayerData.character["class_id"] = int(classes[0]) if not classes.is_empty() else 52
	var races: Array = q.get("races", [])
	if not races.is_empty():
		PlayerData.character["race"] = String(races[0])
	PlayerData.inventory = {}
	PlayerData.set_copper(0)
	var given := 0
	var giver: Npc = await _view(String(q.giver))
	if giver == null:
		return _out(id, q, "no giver in zone", given)
	if not eng.qualifies(q):
		return _out(id, q, "not qualified", given)
	eng.on_interact(giver)
	eng.on_keyword(giver, String(q.accept))
	if not PlayerData.quests.has(id):
		return _out(id, q, "accept failed", given)
	var guard := 0
	while PlayerData.quests.has(id) and guard < 40:
		guard += 1
		var n := int(PlayerData.quests[id].step)
		var st: Dictionary = eng.step_of(id)
		var before := n
		var custom: Dictionary = st.get("custom", {})
		var t := String(st.get("type", ""))
		if not custom.is_empty():
			given += await _custom(id, st, custom)
		elif t.begins_with("kill"):
			var sp: Dictionary = st.get("spawn", {})
			if not sp.is_empty() and int(sp.get("zone", -1)) == int(viewer.zone.info.id):
				viewer.player.global_position = Vector3(sp.pos[0], viewer.zone.height_at(sp.pos[0], sp.pos[2]) + 0.3, sp.pos[2])
				await get_tree().create_timer(2.5).timeout             # the quest brings its monster
			var target := _state(String(st.target))
			if target == null and not sp.is_empty():           # a quest event monster in another zone: a stand-in
				cross_zone += 1
				target = NpcState.new(-1, {"name": String(sp.name), "level": int(sp.get("level", 1)), "realm": 0,
						"pos": sp.get("pos", [0, 0, 0]), "heading": 0, "stats": [0, 0, 0, 0]}, {})
			if target == null:
				return _out(id, q, "step %d kill: no '%s' in zone" % [n, st.target], given)
			for i in 30:
				eng.on_kill(target)
				if not PlayerData.quests.has(id) or int(PlayerData.quests[id].step) != before:
					break
			if viewer.args.has("quest") and PlayerData.quests.has(id) and int(PlayerData.quests[id].step) == before:
				print("[runner] debug kill: target '", target.spawn.name, "' step ", eng.step_of(id), " slots ", PlayerData.free_slots())
		elif t.begins_with("interact") or t.begins_with("whisper"):
			var v: Npc = await _view(String(st.target))
			if v == null:
				return _out(id, q, "step %d %s: no '%s' in zone" % [n, t, st.target], given)
			if t.begins_with("interact"):
				eng.on_interact(v)
			else:
				eng.on_keyword(v, String(st.advance))
		elif t.begins_with("deliver") or t.begins_with("collect"):
			var v: Npc = await _view(String(st.target))
			if v == null:
				return _out(id, q, "step %d %s: no '%s' in zone" % [n, t, st.target], given)
			var want := String(st.collect) if String(st.collect) != "" else String(st.step_item)
			var slot := PlayerData.find_item(want)
			if slot < 0 and want != "":
				if ItemDb.item(want).is_empty():
					return _out(id, q, "step %d %s: item '%s' missing from the data" % [n, t, want], given)
				PlayerData.inventory[PlayerData.first_free()] = {"id": want, "count": 1}
				given += 1
				slot = PlayerData.find_item(want)
			eng.on_give(v, slot)
		elif t.begins_with("search"):
			var area: Dictionary = st.get("search", {})
			if area.is_empty():
				return _out(id, q, "step %d search: no area" % n, given)
			if int(area.get("zone", -1)) != int(viewer.zone.info.id):
				cross_zone += 1                                 # the area is in another zone: count the search done there
				if String(st.type) == "search_finish":
					eng._finish(id, null)
				else:
					eng._advance(id, null)
				continue
			viewer.player.global_position = Vector3(area.pos[0], viewer.zone.height_at(area.pos[0], area.pos[2]) + 0.3, area.pos[2])
			viewer.player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			for i in 10:
				eng.search()
				await get_tree().create_timer(float(area.get("seconds", 5)) + 0.3).timeout
				if not PlayerData.quests.has(id) or int(PlayerData.quests[id].step) != before:
					break
		else:
			return _out(id, q, "step %d: unknown type %s" % [n, t], given)
		if PlayerData.quests.has(id) and int(PlayerData.quests[id].step) == before:
			return _out(id, q, "step %d %s did not advance" % [n, (custom.get("kind", t))], given)
	return _out(id, q, "done" if not PlayerData.quests.has(id) and PlayerData.quests_done.has(id) else "loop", given)


func _custom(id: String, st: Dictionary, c: Dictionary) -> int:
	var given := 0
	match String(c.kind):
		"use_item", "travel", "say":
			if c.has("zone") and int(c.zone) != int(viewer.zone.info.id) and FileAccess.file_exists("res://content/zones/zone%03d/zone.json" % int(c.zone)):
				cross_zone += 1                                 # the place is in another built zone: count it done there
				eng._advance(id, null)
				return given
			if c.has("zone") and int(c.zone) == int(viewer.zone.info.id):
				viewer.player.global_position = Vector3(c.pos[0], viewer.zone.height_at(c.pos[0], c.pos[2]) + 0.3, c.pos[2])
				await get_tree().physics_frame
			if String(c.kind) == "use_item":
				if PlayerData.find_item(String(c.item)) < 0:
					PlayerData.inventory[PlayerData.first_free()] = {"id": String(c.item), "count": 1}
					given += 1
				PlayerData.item_used.emit(String(c.item))
			elif String(c.kind) == "say":
				if bool(c.get("nightonly", false)):
					viewer.sky.set_hour(23.0) if viewer.sky.has_method("set_hour") else null
				eng.on_say(String(c.get("words", "")))
			else:
				await get_tree().create_timer(1.2).timeout
		"has_item":
			PlayerData.inventory[PlayerData.first_free()] = {"id": String(c.item), "count": 1}
			given += 1
			await get_tree().create_timer(1.2).timeout
		"choose":
			var v: Npc = await _view(String(c.target))
			if v:
				eng.on_keyword(v, String((c.get("choices", {}) as Dictionary).keys()[0]))
		"trade":
			var v: Npc = await _view(String(c.target))
			var want := String((c.get("trades", {}) as Dictionary).keys()[0])
			if v:
				if PlayerData.find_item(want) < 0:
					PlayerData.inventory[PlayerData.first_free()] = {"id": want, "count": 1}
					given += 1
				eng.on_give(v, PlayerData.find_item(want))
		"interact":
			var v: Npc = await _view(String(c.target))
			if v:
				eng.on_interact(v)
		"quest":
			for nm in String(c.get("quest", "")).split("|", false):
				for other in QuestDb.all():
					if String(QuestDb.quest(other).name).to_lower() == String(nm).strip_edges().to_lower():
						PlayerData.quests_done[String(other)] = 1
			await get_tree().create_timer(1.2).timeout
		"die_to":
			eng.on_player_died(String(c.get("target", "")))
	return given


func _state(npc_name: String) -> NpcState:
	for s in viewer.npcs.states:
		if String((s as NpcState).spawn.name).to_lower() == npc_name.to_lower() and (s as NpcState).alive:
			return s
	var other := _elsewhere(npc_name)                      # in another built zone: a stand-in for the test
	if not other.is_empty():
		cross_zone += 1
		return NpcState.new(-1, other, {})
	return null


var cross_zone := 0
var _others := {}


func _elsewhere(npc_name: String) -> Dictionary:
	if _others.is_empty():
		var zones := []
		for dname in DirAccess.get_directories_at("res://content/zones"):     # every built zone
			if dname.begins_with("zone") and dname.substr(4).is_valid_int():
				zones.append(int(dname.substr(4)))
		for z in zones:
			if z == int(viewer.zone.info.id) or not FileAccess.file_exists("res://content/zones/zone%03d/npcs.json" % z):
				continue
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zone%03d/npcs.json" % z))
			for sp in (d.get("spawns", []) if d is Dictionary else []):
				if not _others.has(String(sp.name).to_lower()):
					_others[String(sp.name).to_lower()] = sp
	return _others.get(npc_name.to_lower(), {})


func _view(npc_name: String) -> Npc:
	var st := _state(npc_name)
	if st == null:
		return null
	if st.index < 0:                                         # the stand-in for an NPC in another zone
		var fake := Npc.new()
		fake.spawn = st.spawn
		add_child(fake)
		fake.visible = false
		return fake
	viewer.player.global_position = st.pos + Vector3(1.5, 0.3, 0)
	for i in 50:
		await get_tree().create_timer(0.1).timeout
		if st.view:
			return st.view
	return null


func _out(id: String, q: Dictionary, result: String, given: int) -> Array:
	log_lines.append("%s %s (L%d, giver %s): %s%s" % [id, q.name, int(q.min), q.giver, result, ("  [%d items given]" % given) if given > 0 else ""])
	print("[runner] ", log_lines[-1])
	return [result.split(":")[0] if result != "done" else "done", given]
