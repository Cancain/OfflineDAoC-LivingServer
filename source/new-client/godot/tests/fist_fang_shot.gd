extends Node3D
## Debug (owner 2026-10-17: fist weapons stab forward): eight Norse figures in the h2h combat stance, each with one fist
## weapon in both hands (the turned ones: fang greave, great fang greave, moon claw, moon fang, great moon fang, lab
## slash, Pict slash, and the claw greave for comparison), seen from the side and the front - user://fist_stab_<view>.png
const IDS := [963, 964, 970]
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	add_child(sun)
	for i in IDS.size():
		var f := Fig3Figure.new()
		f.position = Vector3(0, 0, -1.6 + i * 1.6)
		add_child(f)
		f.load_figure("nor_f")
		var id: int = IDS[i]
		var shield := int(WeaponModels.info(id).get("shield", 0)) > 0
		var item_at := func(slot: int) -> Dictionary:
			if slot == 10:
				return {"model": id}
			if slot == 11:
				return {"model": id, "object_type": 42 if shield else 0}
			return {}
		Player.dress(f, item_at, "standard", true, false)
		var ap := f.model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("combat_idle_h2h")
		ap.seek(0.0, true)
		var l := Label3D.new()
		l.text = "%d %s" % [id, String(WeaponModels.info(id).get("nif", "")).replace("n_hth_", "")]
		l.font_size = 48
		l.pixel_size = 0.003
		l.position = f.position + Vector3(0, 2.1, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for v in [["side", Vector3(-3.6, 1.3, 0), Vector3(0, 1.1, 0)], ["front", Vector3(1.6, 1.3, 3.2), Vector3(0, 1.1, 1.0)]]:
		cam.position = v[1]
		cam.look_at(v[2])
		await get_tree().create_timer(0.7).timeout
		get_viewport().get_texture().get_image().save_png("user://fist_fang_%s.png" % v[0])
	get_tree().quit()
