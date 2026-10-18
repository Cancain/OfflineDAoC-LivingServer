extends Node3D
## Debug (owner 2026-10-17: bone deadeyes, model 920 skel02, drawn solid black): the model as NpcManager loads it,
## plain (left) and with Npc.ghost_look (right), plus skel01 (middle) - user://skel_black.png. Runs once.
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var paths := ["res://content/monsters/skel02__skel02/model.gltf", "res://content/monsters/skel01__skel1/model.gltf",
			"res://content/monsters/skel02__skel02/model.gltf"]
	for i in 3:
		var ps := NpcManager._pack_model(paths[i])
		var m := ps.instantiate() as Node3D
		m.position = Vector3(-1.2 + 1.2 * i, 0, 0)
		add_child(m)
		if i == 2:
			Npc.ghost_look(m, false)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			(aps[0] as AnimationPlayer).play("idle")
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mat := (mi as MeshInstance3D).get_active_material(0)
			print("[skel] ", paths[i].get_base_dir().get_file(), " ", mat, " tex ", (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(0, 1.0, 4.0)
	cam.look_at(Vector3(0, 0.8, 0))
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://skel_black.png")
	get_tree().quit()
