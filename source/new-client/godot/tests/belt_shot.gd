extends Node3D
## Debug: weapons on the belt - the Bonedancer commander with its axe (3469) and a Norse figure with a hand axe (2),
## both on Bip01 L Belt, seen from behind and from the side (user://belt_<view>.png). --frames: WeaponModels frames on.
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.9, 0.9)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://content/monsters/bonedancerpet__bonedancerpet01/model.gltf"), st)
	var bd := doc.generate_scene(st) as Node3D
	bd.position = Vector3(-0.8, 0, 0)
	add_child(bd)
	var f := Fig3Figure.new()
	f.position = Vector3(0.8, 0, 0)
	add_child(f)
	f.load_figure("nor_m")
	for root in [bd, f.model]:
		var ap := (root as Node).find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("idle")
		ap.seek(0.0, true)
	WeaponModels.attach(bd, "Bip01 L Belt", 3469)
	WeaponModels.attach(f.model, "Bip01 L Belt", 2)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for v in [["behind", Vector3(0, 1.1, -3.2)], ["side", Vector3(-3.4, 1.1, 0.2)], ["front", Vector3(0, 1.1, 3.2)]]:
		cam.position = v[1]
		cam.look_at(Vector3(0, 0.9, 0))
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png("user://belt_%s.png" % v[0])
	get_tree().quit()
