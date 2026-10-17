extends SceneTree
## Debug: a race figure in each of its skin tones, side by side (owner 2026-10-11: red-faced Celt bots).
##   --path godot --screen 1 -s res://tests/skin_tone_shots.gd -- --prefix=cel_m --out=<file.png>
func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var prefix := String(args.get("prefix", "cel_m"))
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.55, 4.2)
	cam.fov = 36
	root3.add_child(cam)
	cam.look_at(Vector3(0, 1.45, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 20, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.45, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root3.add_child(env)
	var n: int = (CharacterFactory.figure_meta(prefix).get("skin_tones", []) as Array).size()
	for i in n:
		var f := Fig3Figure.new()
		root3.add_child(f)
		f.load_figure(prefix)
		f.apply({"skin": i, "face": 0})
		f.position = Vector3((i - (n - 1) * 0.5) * 0.5, 0, 0)
		f.play("idle")
	for k in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(String(args.get("out", "user://skins.png")))
	quit()
