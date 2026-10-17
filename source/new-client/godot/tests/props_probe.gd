extends Node
## Debug (owner 2026-10-10: check the 30 server props the scan thinks float): for each spot of this zone in
## --spots=<json file>, the gap between the prop and the first floor / wall / roof under it, and a picture.
##   --screen 1 --skip-login --zone=N --probe=props_probe --spots=<file> --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(7.0).timeout
	var all = JSON.parse_string(FileAccess.get_file_as_string(String(v.args.get("spots", ""))))
	var mine: Array = (all as Dictionary).get(str(int(v.zone.info.id)), [])
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.far = 2000.0
	for i in mine.size():
		var s: Array = mine[i]
		var at := Vector3(s[0], s[1], s[2])
		v.player.global_position = at + Vector3(6, 0, 6)
		v.player.hold()
		await get_tree().create_timer(1.5).timeout
		var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.3, 0), at - Vector3(0, 60, 0), ZoneLoader.LAYER_FLOOR | ZoneLoader.LAYER_WALL)
		var hit := space.intersect_ray(q)
		var gap: float = (at.y - (hit.position as Vector3).y) if not hit.is_empty() else 99.0
		var to_center := (Vector3(v.zone.info.size_m * 0.5, at.y, v.zone.info.size_m * 0.5) - at)
		to_center.y = 0
		to_center = to_center.normalized() if to_center.length() > 1 else Vector3(1, 0, 0)
		cam.global_position = at + to_center * 9.0 + Vector3(0, 3.0, 0)
		cam.look_at(at + Vector3(0, 0.8, 0))
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/prop_%d_%d.png" % [String(v.args.get("out", "user://")), int(v.zone.info.id), i])
		print("[prop] zone ", int(v.zone.info.id), " #", i, " ", s[3], " gap to what's under it ", snappedf(gap, 0.1), " m (",
				String(hit.collider.name) if not hit.is_empty() else "nothing", ")")
	get_tree().quit()
