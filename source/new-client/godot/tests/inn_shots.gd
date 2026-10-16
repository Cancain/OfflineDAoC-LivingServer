extends Node
## Debug (bot plan phase 6): pictures of this zone's roadside inn (content/companions/inns.json) - from the road, from
## above, the doorway looking in, the horn platform - and the NPCs near it.
##   --screen 1 --skip-login --zone=202 --figure=cel_m --probe=inn_shots --out=<folder>
func _ready() -> void:
	var v := get_tree().current_scene
	var zid := int(v.zone.info.id)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/inns.json"))
	var inn: Dictionary = {}
	for k in (data as Dictionary).inns:
		if int(data.inns[k].zone) == zid:
			inn = data.inns[k]
	if inn.is_empty():
		print("[inn] no inn in zone ", zid)
		get_tree().quit()
		return
	var p: Player = v.player
	var site := Vector3(float(inn.site[0]), float(inn.ground[1]), float(inn.site[1]))
	var door := Vector3(float(inn.door[0]), float(inn.door[1]), float(inn.door[2]))
	var road := Vector3(float(inn.road[0]), site.y, float(inn.road[1]))
	var horn := Vector3(float(inn.horn.pos[0]), site.y, float(inn.horn.pos[1]))
	road.y = v.zone.height_at(road.x, road.z)
	horn.y = v.zone.height_at(horn.x, horn.z)
	p.global_position = Vector3(float(inn.arrive[0]), float(inn.arrive[1]) + 0.5, float(inn.arrive[2]))
	p.hold()
	await get_tree().create_timer(8.0).timeout              # views, NPCs settle
	var near := []
	for s in v.npcs.states:
		var st: NpcState = s
		if st.pos.distance_to(site) < 60.0 and int(st.spawn.realm) != 0:
			near.append("%s <%s> %s at %s" % [st.spawn.name, st.spawn.get("guild", ""), st.spawn.get("role", ""), st.pos.snapped(Vector3.ONE * 0.1)])
	print("[inn] %d realm NPCs near: \n  %s" % [near.size(), "\n  ".join(near)])
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.fov = 70
	var out := String(v.args.get("out", "user://inn"))
	DirAccess.make_dir_recursive_absolute(out)
	var away := (road - site)
	away.y = 0
	away = away.normalized()
	var side := Vector3(-away.z, 0, away.x)
	var views := {
		"1_from_road": [road + away * 6.0 + side * 18.0 + Vector3(0, 6, 0), site + Vector3(0, 4, 0)],
		"2_above": [site + away * 30.0 + Vector3(0, 55, 0), (site + horn) * 0.5],
		"3_door": [door + (door - site).normalized() * 7.0 + Vector3(0, 1.8, 0), door + (site - door).normalized() * 6.0 + Vector3(0, 1.4, 0)],
		"4_horn": [horn + (road - horn).normalized() * 14.0 + Vector3(0, 5, 0), horn + Vector3(0, 1.5, 0)],
		"5_inside": [site + Vector3(0, float(inn.door[1]) - site.y + 1.8, 0) + (door - site).normalized() * 3.0, site + (site - door).normalized() * 6.0 + Vector3(0, 1.4, 0)],
	}
	for k in views:
		cam.global_position = views[k][0]
		cam.look_at(views[k][1])
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("%d_%s.png" % [zid, k]))
	print("[inn] shots in ", out)
	get_tree().quit()
