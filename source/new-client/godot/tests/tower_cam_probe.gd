extends Node
## Debug: a free camera 25 m from the guard tower at 486, 659 looking at it; also the terrain height under it.
##   --screen 1 --skip-login --zone=0 --probe=tower_cam_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var tower := Vector3(486.4, 70.45, 659.2)
	v.player.global_position = tower + Vector3(0, 0, 40)
	await get_tree().create_timer(2.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.far = 2000.0
	var owner_spot := Vector3(21948 * 0.025, 0, 35788 * 0.025)
	for i in 3:
		var d: float = [240.0, 100.0, 30.0][i]
		var at: Vector3 = tower + (owner_spot - tower).normalized() * d
		at.y = v.zone.height_at(at.x, at.z) + 2.0
		cam.global_position = at
		cam.look_at(tower + Vector3(0, 12, 0))
		cam.current = true
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/towercam_%d.png" % [String(v.args.get("out", "user://")), i])
	var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(tower + Vector3(0, 200, 0), tower - Vector3(0, 50, 0))
	var hit := space.intersect_ray(q)
	print("[towercam] first thing straight down onto the tower: ", hit.get("position"), " ", hit.get("collider"))
	get_tree().quit()
