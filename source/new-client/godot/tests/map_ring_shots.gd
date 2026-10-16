extends Node
## Debug (windowed): the map window (dropdown, FOLLOW, quest dots) and the quest rings under NPCs at the Lethantis tower.
##   --screen 1 --skip-login --zone=8 --realm=alb --ui-test --probe=map_ring_shots --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(viewer.args.get("out", "user://maprings"))
	DirAccess.make_dir_recursive_absolute(out)
	var p: Player = viewer.player
	if int(viewer.zone.info.id) == 8:
		p.global_position = Vector3(14134 * 0.025, 2292 * 0.025 + 0.3, 6483 * 0.025 - 6.0)
	else:                                                # beside the nearest NPC with a ring (Mag Mell's quest givers)
		await get_tree().create_timer(2.5).timeout
		var mk: QuestMarkers = viewer.ui.find_children("*", "QuestMarkers", true, false)[0]
		var best: NpcState = null
		for st in mk._marked:
			if best == null or (st as NpcState).pos.distance_to(p.global_position) < best.pos.distance_to(p.global_position):
				best = st
		print("[rings] marked: ", mk._marked.size(), " nearest ", best.spawn.name if best else "-", " ", mk._marked.get(best, ""))
		if best:
			p.global_position = best.pos + Vector3(0, 0.3, 4.0)
	p.char_yaw = PI
	p.cam_yaw = PI
	p.cam_pitch = -0.45
	p.cam_distance = 7.0
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(out + "/rings.png")
	var mw: MapWindow = viewer.ui.map_window
	mw.show_window()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out + "/map_here.png")
	mw._pick.select(1)
	mw._pick.item_selected.emit(mw._pick.selected)
	for i in mw._entries.size():                         # another zone's map: Salisbury Plains' quest dots
		if (mw._entries[i] as Dictionary).get("id", -1) == 1:
			mw._show(mw._entries[i], true)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out + "/map_other.png")
	mw._pick.show_popup()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out + "/map_dropdown.png")
	get_tree().quit()
