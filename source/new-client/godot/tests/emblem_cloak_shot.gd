extends Node3D
## Debug (owner 2026-10-17: guild emblems on cloaks): two Briton figures in cloak 57 (cat_cloak) - left plain, right
## with a guild emblem on its cloak and heater shield (60) - from behind and the front: user://emblem_cloak_<view>.png.
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 160, 0)
	add_child(sun)
	var e := Emblems.encode(8, 0, 4, 3)
	for i in 2:
		var f := Fig3Figure.new()
		f.position = Vector3(-0.6 + 1.2 * i, 0, 0)
		add_child(f)
		f.load_figure(String(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else "bri_m")
		var em := e if i == 1 else 0
		var item_at := func(slot: int) -> Dictionary:
			match slot:
				26: return {"model": 57, "emblem": em}
				11: return {"model": 60, "emblem": em, "object_type": 42}
				10: return {"model": 1}
			return {}
		Player.dress(f, item_at, "standard", true, true)
		var ap := f.model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("idle")
		ap.seek(0.0, true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for v in [["back", Vector3(0, 1.2, -3.0)], ["front", Vector3(0, 1.2, 3.0)]]:
		cam.position = v[1]
		cam.look_at(Vector3(0, 1.0, 0))
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("user://emblem_cloak_%s.png" % v[0])
	get_tree().quit()
