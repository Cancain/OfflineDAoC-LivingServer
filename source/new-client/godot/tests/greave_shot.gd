extends Node3D
## Debug (owner 2026-10-17: the Savage's claws): two Norse figures in the hand-to-hand combat pose with a Claw Greave
## (963) in each hand - left figure the old way (both on the Held / Shield bones by their HELD grip), right figure the
## new way (Player.dress: greaves on Bip01 R / L Shield, the left one by its HELD2 grip). user://greave_<view>.png.
const MODEL := 963


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
	var figs: Array = []
	for x in [-0.75, 0.75]:
		var f := Fig3Figure.new()
		f.position = Vector3(x, 0, 0)
		add_child(f)
		f.load_figure("nor_m")
		figs.append(f)
		var ap := f.model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var clip := "combat_idle_h2h" if ap.has_animation("combat_idle_h2h") else "combat_idle"
		print("[greave] clip ", clip)
		ap.play(clip)
		ap.seek(0.0, true)
	WeaponModels.attach(figs[0].model, "Bip01 R Held", MODEL)            # before
	WeaponModels.attach(figs[0].model, "Bip01 L Shield", MODEL)
	var item_at := func(slot: int) -> Dictionary:
		return {"model": MODEL} if slot == 10 or slot == 11 else {}
	var made: Array = Player.dress(figs[1].model, item_at, "standard", true, false)   # after
	for a in made:
		print("[greave] after: ", (a as BoneAttachment3D).bone_name)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for v in [["front", Vector3(0, 1.2, 3.0)], ["side", Vector3(-3.2, 1.2, 0.6)], ["back", Vector3(0, 1.2, -3.0)]]:
		cam.position = v[1]
		cam.look_at(Vector3(0, 1.0, 0))
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("user://greave_%s.png" % v[0])
	get_tree().quit()
