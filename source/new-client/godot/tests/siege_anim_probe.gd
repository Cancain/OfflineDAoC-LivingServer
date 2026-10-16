extends Node
## Debug (owner 2026-10-14: siege animations, war map fights): on the running server with Claude's GM test account -
## a heavy ram (/siegeweapon create heavyram) drawn with its animated copy, its clips, the server's arming / loading
## played on it; then the war map on the Albion page with the server's fights plus two sample entries (screenshots
## user://siege_anim_<n>.png).
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind in ["siege_anim", "warmap_fights"]:
			print("[siege] packet ", kind, " ", str(d).left(200)))
	await _wait(8.0)
	var sw: ServerWorld = v.npcs
	Server.command("/jump to 654300 293500 4870 1")
	await _wait(12.0)
	Server.command("/siegeweapon create heavyram")
	await _wait(3.0)
	var ram: NpcState = null
	for st in sw.by_oid.values():
		if (st as NpcState).info.has("object_model") and int((st as NpcState).info.object_model) == 2602:
			ram = st
	for _i in 10:
		if ram and ram.view:
			break
		await _wait(1.0)
	if ram == null or ram.view == null:
		var objs := []
		for st in sw.by_oid.values():
			if (st as NpcState).info.has("object_model") or String((st as NpcState).spawn.name).to_lower().contains("ram"):
				objs.append([st.spawn.name, st.spawn.model, st.info, st.view != null, st.pos.distance_to(v.player.global_position)])
		print("[siege] no ram view; siege objects: ", objs)
		get_tree().quit()
		return
	var n: Npc = ram.view
	print("[siege] ram clips: ", n.anim.get_animation_list() if n.anim else "none", "  playing: ", n.anim.current_animation if n.anim else "")
	sw.select(n)
	sw.interact(n)                                          # take control: the server arms it (action 2 -> "load")
	await _wait(1.5)
	print("[siege] after taking control, playing: ", n.anim.current_animation if n.anim else "")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://siege_anim_1.png")
	await _wait(2.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://siege_anim_2.png")
	Server.client.call("SiegeCommand", 8, 0)
	await _wait(2.0)
	# the war map: Albion's page, the server's fights and two samples on Hadrian's Wall (zone 15) / Forest Sauvage (11)
	v.ui.warmap.show_window()
	v.ui.warmap.show_realm("alb")
	await _wait(3.0)
	var f: Array = v.ui.warmap.fights.duplicate()
	print("[siege] server fights: ", f)
	f.append({"zone": 15, "x": 1, "y": 2, "color": 1, "size": 2, "group": false})
	f.append({"zone": 11, "x": 2, "y": 1, "color": 1, "size": 2, "group": true})
	v.ui.warmap.server_update("warmap_fights", {"fights": f})
	await _wait(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://siege_anim_3.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
