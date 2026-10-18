extends Node3D
## Debug (owner 2026-10-17: guild emblems): emblem shields drawn as the client - no emblem, then four emblems (each
## pattern, different colours and logos) - user://emblem_shields.png. Runs once.
const SHIELDS := [60, 79, 59, 61, 60]
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.33, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 20, 0)
	add_child(sun)
	var emblems := [0, Emblems.encode(8, 0, 0, 3), Emblems.encode(2, 1, 4, 0), Emblems.encode(150, 2, 8, 6),
			Emblems.encode(30, 3, 15, 1)]
	for i in SHIELDS.size():
		var w := WeaponModels.make(SHIELDS[i])
		if w == null:
			print("[emb] no model ", SHIELDS[i])
			continue
		WeaponModels.set_emblem(w, SHIELDS[i], emblems[i])
		var holder := Node3D.new()
		holder.position = Vector3(-2.0 + i * 1.0, 1.0, 0)
		holder.scale = Vector3.ONE * 0.03                # (NIF units, lying on its back: stood up facing the camera)
		holder.rotation_degrees = Vector3(-90, 0, 0)
		add_child(holder)
		holder.add_child(w)
		var aabb := AABB()
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			aabb = aabb.merge((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()) if aabb.size != Vector3.ZERO else (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		print("[emb] ", SHIELDS[i], " emblem ", emblems[i], " aabb ", aabb)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(0, 1.0, 4.2)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("user://emblem_shields.png")
	cam.position = Vector3(0, 1.0, -4.2)
	cam.look_at(Vector3(0, 1.0, 0))
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("user://emblem_shields_back.png")
	get_tree().quit()
