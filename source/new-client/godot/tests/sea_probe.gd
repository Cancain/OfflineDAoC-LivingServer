extends Node
## Debug, local (owner 2026-10-15: Modernagrav's sea see-through to the bottom): from above the zone's spawn, four
## pictures round (user://sea_<n>.png) for the textureless water's depth darkening. Runs once, quits (hard stop 40 s).
func _ready() -> void:
	if get_tree().root.has_meta("sea_ran"):
		return
	get_tree().root.set_meta("sea_ran", true)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.far = 2000.0
	var at := Vector3(float(String(v.args.get("sea_x", "260"))), 159.25 + 14.0, float(String(v.args.get("sea_z", "819"))))
	for i in 4:
		cam.global_position = at
		cam.rotation = Vector3(deg_to_rad(-25), PI / 2.0 + (i - 1.5) * 0.5, 0)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://sea_%d.png" % i)
	print("[sea] done at ", at)
	get_tree().quit()
