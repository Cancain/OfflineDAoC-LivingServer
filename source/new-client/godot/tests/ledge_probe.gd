extends Node
## Debug: measure ground heights (collision ray down) around a spot, to size the step-up height.
## --probe=ledge_probe --at_units=x,y

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var viewer := get_tree().current_scene
	var xy := String(viewer.args.get("at_units", "16606,4358")).split(",")
	var cx := float(xy[0]) * 0.025
	var cz := float(xy[1]) * 0.025
	var space: PhysicsDirectSpaceState3D = viewer.get_world_3d().direct_space_state
	var p: Player = viewer.player
	p.global_position = Vector3(cx, viewer.zone.height_at(cx, cz) + 50.0, cz)   # out of the way of the rays
	await get_tree().physics_frame
	var base := _hit(space, cx, cz, p)
	print("ground at spot: %.3f m (terrain %.3f)" % [base, viewer.zone.height_at(cx, cz)])
	for deg in range(0, 360, 30):
		var line := []
		for d: float in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
			var x := cx + sin(deg_to_rad(deg)) * d
			var z := cz - cos(deg_to_rad(deg)) * d
			line.append("%+.2f" % (_hit(space, x, z, p) - base))
		print("heading %3d: %s" % [deg, " ".join(line)])
	get_tree().quit()


func _hit(space: PhysicsDirectSpaceState3D, x: float, z: float, p: Player) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -400.0, z))
	q.exclude = [p.get_rid()]
	var r := space.intersect_ray(q)
	return r.position.y if r else NAN
