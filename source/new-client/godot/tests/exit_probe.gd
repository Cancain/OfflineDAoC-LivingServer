extends Node
## Debug (owner 2026-10-10 "make sure all the zone entrance and exit areas are working"): every exit of this zone -
## find the floor beside its quad (either side, inside its height range), stand there, walk across the line in small
## steps and see whether the jump fires (the viewer runs with --exit_test: it reports instead of loading the zone).
##   --screen 1 --skip-login --zone=N --figure=cel_m --probe=exit_probe -- --exit_test
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var exits: Array = v.zone.info.get("exits", [])
	var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	for e in exits:
		var lo: Array = e.min
		var hi: Array = e.max
		var a := Vector2(e.a[0], e.a[1]) if e.has("a") else Vector2(lo[0], lo[2])
		var b := Vector2(e.b[0], e.b[1]) if e.has("b") else Vector2(hi[0], hi[2])
		var mid := (a + b) * 0.5
		var along := (b - a).normalized() if a.distance_to(b) > 0.01 else Vector2(1, 0)
		var n := Vector2(-along.y, along.x)
		var result := "no floor within its height range on either side"
		for side in [1.0, -1.0]:
			var at: Vector2 = mid + n * side * 2.0
			var wide: float = 15.0 if v.args.has("wide") else 0.0      # --wide: report floors well above / below the quad
			var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, float(hi[1]) + 1.0 + wide, at.y),
					Vector3(at.x, float(lo[1]) - 3.0 - wide, at.y), ZoneLoader.LAYER_FLOOR)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var fy: float = (hit.position as Vector3).y
			# away from every exit first (arms the exits), then onto the floor beside this one and across it
			v.player.global_position = Vector3(at.x, fy, at.y) + Vector3(n.x, 0, n.y) * side * 30.0
			v.player.hold()
			await get_tree().physics_frame
			await get_tree().process_frame
			await get_tree().process_frame
			v.exit_fired = ""
			var fired := false
			for k in 45:
				var p2: Vector2 = at.lerp(mid - n * side * 1.0, k / 44.0)
				v.player.global_position = Vector3(p2.x, fy + 0.02, p2.y)
				v.player.hold()
				await get_tree().process_frame
				if v.exit_fired == String(e.name):
					fired = true
					break
			result = ("fired" if fired else "DID NOT FIRE") + " from the floor at %.1f m (quad %.1f-%.1f m)" % [fy, lo[1], hi[1]]
			if fired:
				break
		if v.args.has("wide"):                                  # the walls near the quad's middle (anything blocking it)
			for side in [1.0, -1.0]:
				var from: Vector3 = Vector3(mid.x, float(lo[1]) + 1.0, mid.y) + Vector3(n.x, 0, n.y) * side * 3.0
				var wq := PhysicsRayQueryParameters3D.create(from, Vector3(mid.x, float(lo[1]) + 1.0, mid.y), ZoneLoader.LAYER_WALL)
				var wh := space.intersect_ray(wq)
				print("   side ", side, " wall between 3 m out and the quad at quad-bottom+1 m: ",
						"none" if wh.is_empty() else "%s at %.2f m from the quad" % [String(wh.collider.name), (wh.position as Vector3).distance_to(Vector3(mid.x, float(lo[1]) + 1.0, mid.y))])
		print("[exitprobe] zone ", int(v.zone.info.id), " ", e.name, " -> ", e.get("to_zone", "none"), ": ", result)
	get_tree().quit()
