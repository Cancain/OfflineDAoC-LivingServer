extends Node
## Debug (owner 2026-10-10: Shrouded Isles flying stable paths - do the mounts render right, not backwards?): starts
## the given flight from its first point (as the stable master would), lets it fly, then checks the model's facing
## against its direction of travel and takes pictures from behind and from the side.
##   --screen 1 --skip-login --zone=57 --probe=flight_probe --route=Dragonfly_Camp_Clifton --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(v.args.get("out", "user://"))
	var id := String(v.args.get("route", ""))
	var hr: HorseRoutes = v.get_node("HorseRoutes")
	var r: Dictionary = HorseRoutes.routes().get(id, {})
	var start: Vector3 = hr._local(r.points[0])
	var nxt: Vector3 = hr._local(r.points[1])
	v.player.global_position = start + Vector3(0, 0.5, 0)
	await get_tree().create_timer(1.0).timeout
	HorseRoutes.ride = {"path": id, "i": 0, "model": int(r.mount.model), "size": 50, "wait": 4.0,
			"yaw": atan2(nxt.x - start.x, nxt.z - start.z), "rpos": [float(r.points[0][0]), float(r.points[0][1]), start.y]}
	hr._show_horse()
	hr._mount_in = 0.4
	await get_tree().create_timer(9.0).timeout
	var h: Node3D = hr.horse
	var a := h.global_position
	await get_tree().create_timer(0.5).timeout
	var b := h.global_position
	var travel := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var fwd := h.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var cy: float = v.player.char_yaw
	var rider := Vector3(-sin(cy), 0.0, -cos(cy))     # forward = -Z turned by char_yaw
	print("[flight] ", id, " model ", r.mount.model, " speed ", snappedf(a.distance_to(b) / 0.5, 0.1), " m/s, height above ground ",
			snappedf(b.y - v.npcs.ground_at(b), 0.1), " m; model +Z vs travel ", snappedf(rad_to_deg(fwd.angle_to(travel)), 1),
			" deg; rider facing vs travel ", snappedf(rad_to_deg(Vector3(rider.x, 0, rider.z).normalized().angle_to(travel)), 1), " deg; anim ",
			hr._horse_anim.current_animation if hr._horse_anim else "-", "; rider clip ", v.player.ride_clip)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	for view in [["behind", -travel * 7.0 + Vector3(0, 2.5, 0)], ["side", travel.cross(Vector3.UP) * 7.0 + Vector3(0, 1.0, 0)]]:
		cam.global_position = h.global_position + view[1]
		cam.look_at(h.global_position + Vector3(0, 1.0, 0))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/flight_%s_%s.png" % [out, id, view[0]])
	get_tree().quit()
