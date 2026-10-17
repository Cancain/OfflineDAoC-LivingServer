extends Node
## Debug (owner 2026-10-10: ladders were instant with no animation): stand in front of the climb wall nearest --pos,
## hold forward, and log height / climbing / clip each 0.25 s; pictures at the start, mid-climb and the top.
##   --screen 1 --skip-login --zone=0 --figure=cel_m --probe=ladder_probe --near=x,z --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var want := String(v.args.get("near", "0,0")).split(",")
	var target := Vector2(float(want[0]), float(want[1]))
	var body: Node = v.zone.get_node_or_null("ClimbBodies")
	if body == null or body.get_child_count() == 0:
		print("[ladder] no climb walls in this zone"); get_tree().quit(); return
	# the climb shape nearest the spot: its faces in the world, lowest point, centre, facing normal
	var best_faces := PackedVector3Array()
	var best_d := INF
	for cs in body.get_children():
		var faces: PackedVector3Array = ((cs as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
		var x: Transform3D = (cs as CollisionShape3D).global_transform
		var c := Vector3.ZERO
		for f in faces:
			c += x * f
		c /= max(1, faces.size())
		var d := Vector2(c.x, c.z).distance_to(target)
		if d < best_d:
			best_d = d
			best_faces = PackedVector3Array()
			for f in faces:
				best_faces.append(x * f)
	# split into separate ladders: take the lowest triangle's plane
	var lo := best_faces[0]
	var li := 0
	for i in best_faces.size():
		if best_faces[i].y < lo.y:
			lo = best_faces[i]
			li = i
	var t0 := li - li % 3
	var a := best_faces[t0]
	var b := best_faces[t0 + 1]
	var c2 := best_faces[t0 + 2]
	var n := (b - a).cross(c2 - a).normalized()
	n.y = 0
	n = n.normalized()
	var mid := (a + b + c2) / 3.0
	var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	print("[ladder] nearest climb wall %.1f m from the spot, lowest at %.2f m, normal %s" % [best_d, lo.y, n.snapped(Vector3.ONE * 0.01)])
	# the open side (owner 2026-10-10: the climber stood between the ladder and the tower wall, climbing it backwards):
	# the side with the farther wall
	var open := []
	for side in [1.0, -1.0]:
		var from: Vector3 = mid + Vector3(0, 0.8, 0) + n * side * 0.3
		var wq := PhysicsRayQueryParameters3D.create(from, from + n * side * 6.0, ZoneLoader.LAYER_WALL)
		var wh: Dictionary = space.intersect_ray(wq)
		open.append([from.distance_to(wh.position) if not wh.is_empty() else 6.0, side])
	open.sort_custom(func(x, y): return x[0] > y[0])
	print("[ladder] room on each side: ", open)
	for o in open:
		var side: float = o[1]
		var at: Vector3 = mid + n * side * 0.9
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.5, 0), at - Vector3(0, 3, 0), ZoneLoader.LAYER_FLOOR)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		v.player.global_position = hit.position
		v.player.char_yaw = atan2(n.x * side, n.z * side)        # facing the wall (forward = -sin, -cos)
		v.player.hold()
		break
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.6).timeout
	var y0: float = v.player.global_position.y
	v.player.autorun = true
	var shots := 0
	var after := 0
	for k in 60:
		await get_tree().create_timer(0.25).timeout
		var p: Vector3 = v.player.global_position
		var side_v := Vector3(cos(v.player.char_yaw), 0, -sin(v.player.char_yaw))
		cam.global_position = p + side_v * 3.5 + Vector3(0, 1.2, 0)
		cam.look_at(p + Vector3(0, 0.9, 0))
		var anim: AnimationPlayer = v.player.get("_anim")
		print("[ladder] t=%.2f y=%+.2f climbing=%s grounded=%s clip=%s" % [k * 0.25, p.y - y0, v.player.climbing, v.player.grounded,
				anim.current_animation if anim else "-"])
		if (k == 2 or (v.player.climbing and shots == 1) or (not v.player.climbing and k > 4 and shots == 2)) and shots < 3:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/ladder_%d.png" % [String(v.args.get("out", "user://")), shots])
			shots += 1
		if k > 6 and not v.player.climbing:
			after += 1
			if after == 3:
				v.player.autorun = false                    # stepped onto the platform: stand still there
			if after >= 7:
				break
	v.player.autorun = false
	get_tree().quit()
