extends Node
## Debug (owner 2026-10-10: the 1.65 /task system): a level 3 Hibernian asks this level's kill-task guard (tasks.json),
## a wrong guard, kills the target, turns it in; a delivery task from a merchant handed to its receiver; the per-level
## limit; dying with a task; the /task snapshot. Pictures with --out: the marker on the ground and on the map.
##   --screen 1 --skip-login --zone=207 --figure=cel_m --ui-test --probe=task_probe [--out=<folder>]
var v: Node
var out := ""


func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _near(st: NpcState) -> Npc:
	v.player.global_position = st.pos + Vector3(2.0, 0.4, 0)
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		if st.view:
			return st.view
	return null


func _state(name: String) -> NpcState:
	for s in v.npcs.states:
		if String((s as NpcState).spawn.name) == name:
			return s
	return null


func _ready() -> void:
	v = get_tree().current_scene
	out = String(v.args.get("out", ""))
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, k): print("[chat:%s] %s" % [k, t]))
	PlayerData.level = 3
	PlayerData.character.erase(TaskSystem.SAVE)
	PlayerData.character.erase(TaskSystem.DONE)
	var tasks: TaskSystem = v.tasks
	var gname := "Sentinel Andreasa"                     # any named guard of the zone (owner 2026-10-10)
	var gs := _state(gname)
	var guard := await _near(gs)
	v.npcs.target = guard
	print("[task] asking ", gname)
	tasks.command("")
	var t := TaskSystem.current()
	print("[task] task: ", t)
	await get_tree().create_timer(2.5).timeout
	v.ui.map_window.show_window() if v.ui.map_window.has_method("show_window") else null
	await get_tree().create_timer(0.5).timeout
	await _shot("task_given_map")
	# go to the target spot and look at the marker
	var p: Array = t.target_pos
	var mob: NpcState = null
	for s in v.npcs.states:
		if String((s as NpcState).spawn.name) == String(t.mob) and (s as NpcState).pos.distance_to(Vector3(p[0], p[1], p[2])) < 150.0:
			mob = s
			break
	if mob:
		v.player.global_position = mob.pos + Vector3(6.0, 1.0, 6.0)
		await get_tree().create_timer(3.0).timeout
		await _shot("task_target_marker")
		tasks.on_kill(mob)                                  # as if killed
	print("[task] after kill: ", TaskSystem.current().get("killed"), " / ", TaskSystem.describe(TaskSystem.current()))
	guard = await _near(gs)
	var xp0 := PlayerData.xp
	var c0 := PlayerData.total_copper()
	print("[task] turn in: ", tasks.on_interact(guard), " xp +", PlayerData.xp - xp0, " copper +", PlayerData.total_copper() - c0,
			" done this level ", tasks.done_this_level())
	# delivery from a merchant
	var merchant: NpcState = null
	for s in v.npcs.states:
		var st: NpcState = s
		if str(st.spawn.get("role", "")) == "merchant" and int(st.spawn.realm) == PlayerData.realm_id():
			merchant = st
			break
	var mv := await _near(merchant)
	v.npcs.target = mv
	for i in 30:
		tasks._pause_until = 0.0
		tasks.command("")
		if not TaskSystem.current().is_empty():
			break
	t = TaskSystem.current()
	print("[task] delivery from ", merchant.spawn.name, ": ", t.get("receiver"), " item ", t.get("item", {}).get("name"),
			" slot ", PlayerData.find_item(TaskSystem.ITEM_ID))
	var rv := await _near(_state(String(t.receiver)))
	await get_tree().create_timer(2.0).timeout
	await _shot("delivery_receiver_marker")
	print("[task] give: ", tasks.on_give(rv, PlayerData.find_item(TaskSystem.ITEM_ID)), " done this level ", tasks.done_this_level())
	# third task at level 3, then the limit
	guard = await _near(gs)
	v.npcs.target = guard
	tasks.command("")
	print("[task] third: ", TaskSystem.current().get("name"))
	tasks.command("status")
	await get_tree().create_timer(0.5).timeout
	await _shot("task_snapshot")
	tasks.on_player_died("a test")
	print("[task] after death: ", TaskSystem.current(), " done ", tasks.done_this_level())
	tasks.command("")
	get_tree().quit()
