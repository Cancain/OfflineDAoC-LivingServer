extends Node3D
## Debug (owner 2026-10-17: a spirit champion's 1h hammer drawn solid white): a Norse figure with the norse hammer 1H
## (321) plain (left) and with Npc.ghost_look on figure and weapon as a GHOST living gets it (right) -
## user://ghost_weapon.png. Runs once.
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.42, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	for i in 2:
		var f := Fig3Figure.new()
		f.position = Vector3(-0.6 + 1.2 * i, 0, 0)
		add_child(f)
		f.load_figure("nor_m")
		var item_at := func(slot: int) -> Dictionary: return {"model": 321} if slot == 10 else {}
		var made: Array = Player.dress(f, item_at, "standard", true, false)
		if i == 1:
			Npc.ghost_look(f.model, true)
			for w in made:
				Npc.ghost_look(w as Node3D, true)
				for mi in (w as Node).find_children("*", "MeshInstance3D", true, false):
					var m := mi as MeshInstance3D
					print("[gw] surface0 ", m.get_surface_override_material(0), " active ", m.get_active_material(0))
		else:
			for w in made:
				for mi in (w as Node).find_children("*", "MeshInstance3D", true, false):
					var m := mi as MeshInstance3D
					var bm := m.get_active_material(0)
					print("[gw] plain ", bm, " tex ", (bm as BaseMaterial3D).albedo_texture if bm is BaseMaterial3D else "n/a")
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(0, 1.1, 2.4)
	cam.look_at(Vector3(0, 0.9, 0))
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("user://ghost_weapon.png")
	get_tree().quit()
