extends Node
## Debug: a city zone (Tir na Nog). Screens at each spot, the player's floor, and how many NPCs stand on a floor.
##   --skip-login --zone=209 --figure=cel_m --ui-test --probe=city_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(viewer.args.get("out", "user://city"))
	var zone: ZoneLoader = viewer.zone
	print("[city] zone ", zone.info.name, " city ", zone.city, " spots ", viewer._spots.map(func(s): return s.name))
	for i in viewer._spots.size():
		viewer._go_to_spot(i)
		await get_tree().create_timer(3.0).timeout
		var p: Vector3 = viewer.player.global_position
		print("[city] spot ", viewer._spots[i].name, " player at ", p, " floor below ", zone.height_at(p.x, p.z, p.y))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/city_%d.png" % [out, i])
	var on := 0
	var off := []
	for s in viewer.npcs.states:
		var st: NpcState = s
		var g := zone.height_at(st.pos.x, st.pos.z, st.pos.y)
		if absf(g - st.pos.y) < 0.5:
			on += 1
		elif off.size() < 6:
			off.append([st.spawn.name, snappedf(st.pos.y - g, 0.01)])
	print("[city] npcs ", viewer.npcs.states.size(), " on a floor ", on, " off: ", off)
	# a look along the main street from above
	viewer.player.global_position = Vector3(21633 * 0.025, 7916 * 0.025 + 0.3, 24973 * 0.025)
	viewer.player.cam_distance = 14.0
	viewer.player.cam_pitch = -0.45
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/city_overview.png" % out)
	get_tree().quit()
