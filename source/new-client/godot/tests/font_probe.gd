extends Node3D
## Renders name plates in the classic font with a few filter / size options, saves a screenshot, quits.
func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.position = Vector3(0, 0, 5)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.3, 0.2)
	add_child(env)
	var f := ClassicFont.get_font("14font")
	var vp_h := get_viewport().get_visible_rect().size.y
	var opts := [["nearest", BaseMaterial3D.TEXTURE_FILTER_NEAREST, 1.0], ["linear", BaseMaterial3D.TEXTURE_FILTER_LINEAR, 1.0],
			["nearest x2", BaseMaterial3D.TEXTURE_FILTER_NEAREST, 2.0], ["linear x2", BaseMaterial3D.TEXTURE_FILTER_LINEAR, 2.0]]
	for i in opts.size():
		var l := Label3D.new()
		l.font = f
		l.font_size = 14
		l.text = "%s: minor changeling Guardian Trainer il!" % opts[i][0]
		l.fixed_size = true
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.texture_filter = opts[i][1]
		l.pixel_size = 2.0 * tan(deg_to_rad(35.0)) / vp_h * opts[i][2]
		l.shaded = false
		l.position = Vector3(0, 1.5 - i * 0.9, 0)
		add_child(l)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
