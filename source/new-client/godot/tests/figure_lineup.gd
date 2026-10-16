extends Node3D
## Debug: line up Catacombs race figures (Fig3Figure) and save a screenshot.
##   godot --path godot res://tests/figure_lineup.tscn -- --figures=cel_m,tro_f --out=<png> [--look=key:value,...]
##   [--vary=key] one figure per option of `key` (face, hair, hair_color, eyes, skin, tattoo, size)
##   [--close] frame the heads

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	get_window().size = Vector2i(1600, 900)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.22, 0.24, 0.28)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var look := {}
	for kv in String(args.get("look", "")).split(",", false):
		var p := kv.split(":")
		look[p[0]] = int(p[1])
	var names := String(args.get("figures", "cel_m")).split(",", false)
	var figs: Array[Fig3Figure] = []
	if args.has("vary"):
		var probe := Fig3Figure.new()
		add_child(probe)
		probe.load_figure(names[0])
		probe.apply(look)
		var n := probe.option_count(String(args["vary"]))
		probe.queue_free()
		for i in n:
			var f := Fig3Figure.new()
			add_child(f)
			f.load_figure(names[0])
			var l := look.duplicate()
			l[String(args["vary"])] = i
			f.apply(l)
			figs.append(f)
	else:
		for n in names:
			var f := Fig3Figure.new()
			add_child(f)
			if f.load_figure(n):
				f.apply(look)
				figs.append(f)
	args_rest = args.has("rest")
	if args.has("heads"):                                 # one head close-up per figure, tiled into one image
		await _heads(figs, String(args.get("out", "user://heads.png")))
		get_tree().quit()
		return
	var gap := 0.9 if args.has("close") else 1.3
	for i in figs.size():
		figs[i].position = Vector3((i - (figs.size() - 1) * 0.5) * gap, 0, 0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var width := maxf(figs.size() * gap, 2.0)
	if args.has("close"):
		cam.fov = 30
		cam.position = Vector3(0, 1.75, width * 1.6)
		cam.look_at(Vector3(0, 1.65, 0))
	else:
		cam.fov = 40
		cam.position = Vector3(0, 1.3, width * 1.15 + 1.5)
		cam.look_at(Vector3(0, 1.0, 0))
	for f in 45:
		await get_tree().process_frame
	var out := String(args.get("out", "user://lineup.png"))
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " figures ", figs.size())
	get_tree().quit()


var args_rest := false


func _heads(figs: Array[Fig3Figure], out: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 22
	var tile := 400
	var cols := mini(figs.size(), 8)
	var rows := int(ceil(figs.size() / float(cols)))
	var sheet := Image.create(tile * cols, tile * rows, false, Image.FORMAT_RGBA8)
	for f in figs:
		f.visible = false
	for i in figs.size():
		var f := figs[i]
		f.visible = true
		f.position = Vector3.ZERO
		if f.anim and args_rest:                          # --rest: the bind pose, no animation
			f.anim.stop()
			for s3 in f.model.find_children("*", "Skeleton3D", true, false):
				(s3 as Skeleton3D).reset_bone_poses()
		elif f.anim:                                      # hold an idle frame
			f.anim.seek(1.0, true)
			f.anim.pause()
		await get_tree().process_frame
		var sk := f.model.find_children("*", "Skeleton3D", true, false)
		var head := Vector3(0, 1.6, 0)
		if sk.size() > 0:
			var s3: Skeleton3D = sk[0]
			var b := s3.find_bone("Bip01 Head")
			if b >= 0:
				head = s3.global_transform * s3.get_bone_global_pose(b).origin
		cam.position = head + Vector3(0, 0.03, 0.75 * f.scale.x)
		cam.look_at(head + Vector3(0, 0.03, 0))
		for k in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var sq := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - sq) / 2, (img.get_height() - sq) / 2, sq, sq))
		img.resize(tile, tile)
		img.convert(Image.FORMAT_RGBA8)                   # blit_rect needs matching formats
		sheet.blit_rect(img, Rect2i(0, 0, tile, tile), Vector2i((i % cols) * tile, (i / cols) * tile))
		f.visible = false
	sheet.save_png(out)
	print("saved ", out, " heads ", figs.size())
