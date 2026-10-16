extends Node
## Debug (owner 2026-10-10: Camelot Hills brit_shop door - no collision, no click): finds the door nearest the
## player, checks a wall ray hits it, clicks it through the viewer, checks it opens and its collision swings away.
##   --screen 1 --skip-login --zone=0 --pos=278.85,65.5,753.95 --figure=bri_m --probe=door_probe [--out=dir]
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var best: ZoneDoor = null
	for d in v.zone.doors:
		if best == null or (d as ZoneDoor).global_position.distance_to(v.player.global_position) < best.global_position.distance_to(v.player.global_position):
			best = d
	print("[door] doors in zone ", v.zone.doors.size(), "; nearest at ", best.global_position, " dist ",
			best.global_position.distance_to(v.player.global_position))
	var c := best.global_position + Vector3(0, 1.0, 0)
	var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	var hits := 0
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(c + dir * 2.0, c - dir * 2.0, ZoneDoor.PICK_LAYER)
		if not space.intersect_ray(q).is_empty():
			hits += 1
	print("[door] rays through the leaf that hit it: ", hits, " of 4")
	var q2 := PhysicsRayQueryParameters3D.create(c + Vector3(0, 0, 2.5), c - Vector3(0, 0, 2.5), ZoneDoor.PICK_LAYER)
	var q3 := PhysicsRayQueryParameters3D.create(c + Vector3(2.5, 0, 0), c - Vector3(2.5, 0, 0), ZoneDoor.PICK_LAYER)
	var h: Dictionary = space.intersect_ray(q2)
	if h.is_empty():
		h = space.intersect_ray(q3)
	print("[door] the click ray finds a door: ", not h.is_empty() and h.collider.has_meta("door"))
	var before := best.global_transform
	print("[door] sound flag ", best.sound_flag, "  camera to door ", v.player.camera.global_position.distance_to(best.closed.origin), " m")
	v.player.camera.global_position = best.closed.origin + Vector3(2.0, 1.5, 2.0)
	(h.collider.get_meta("door") as ZoneDoor).toggle()
	await get_tree().process_frame
	var players := best.get_parent().find_children("*", "AudioStreamPlayer3D", false, false).filter(func(p): return p.playing)
	print("[door] door sounds playing: ", players.map(func(p): return p.stream.resource_path if p.stream.resource_path != "" else str(p.stream.get_length()) + " s"))
	await get_tree().create_timer(1.5).timeout
	print("[door] open=", best.is_open, "  leaf turned ", rad_to_deg(before.basis.z.angle_to(best.global_transform.basis.z)), " deg")
	print("[door] the same rays now hit: ", int(not space.intersect_ray(q2).is_empty()) + int(not space.intersect_ray(q3).is_empty()))
	get_tree().quit()
