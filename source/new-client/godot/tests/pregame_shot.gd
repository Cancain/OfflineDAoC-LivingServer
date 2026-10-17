extends Node3D
## Debug: render a character-select backdrop from several camera positions to work out the client's framing.
##   godot --path godot res://tests/pregame_shot.tscn -- --realm=hib --out=<prefix>
##   optional --cam=x,y,z;tx,ty,tz  (metres, Godot axes) for one specific view

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var realm := String(args.get("realm", "hib"))
	get_window().size = Vector2i(1600, 900)
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://content/pregame/pregame.json"))
	var scene := NifScene.new()
	add_child(scene)
	scene.load_scene("res://content/pregame/%s/scene.gltf" % realm)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.9
	var fog: Dictionary = meta.fog.get(realm, {})
	if not fog.is_empty():
		e.fog_enabled = true
		e.fog_light_color = Color(fog.color[0], fog.color[1], fog.color[2])
		e.fog_density = float(fog.density) * 0.00012
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "50"))
	cam.far = 3000.0
	add_child(cam)
	cam.make_current()
	var views := []
	var spot := Vector3(-3.5, -4.98, 0.0)                 # client character spot = the scene's collision floor
	if args.has("top"):                                  # --top=x,z,size : orthographic view straight down
		var t := String(args["top"]).split(",")
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(t[2])
		views.append([Vector3(float(t[0]), 200.0, float(t[1])), Vector3(float(t[0]), 0.0, float(t[1]) - 0.001)])
		var marker := MeshInstance3D.new()                # red post at the character spot 
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.4
		cyl.height = 30.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.RED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cyl.material = mat
		marker.mesh = cyl
		marker.position = spot
		add_child(marker)
		e.fog_enabled = false
	elif args.has("ring"):                               # --ring=dist,height : 8 headings around the character spot
		var r := String(args["ring"]).split(",")
		for k in 8:
			var ang := TAU * k / 8.0
			views.append([spot + Vector3(sin(ang) * float(r[0]), float(r[1]), cos(ang) * float(r[0])), spot + Vector3(0, 1.0, 0)])
		var post := MeshInstance3D.new()                  # a 1.8 m stand-in figure at the spot
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.8
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color.RED
		cap.material = pm
		post.mesh = cap
		post.position = spot + Vector3(0, 0.9, 0)
		add_child(post)
	elif args.has("orbit"):                              # --orbit=dist,height,heading_deg[,aim_height]
		var o := String(args["orbit"]).split(",")
		var ang := deg_to_rad(float(o[2]))
		var aim := float(o[3]) if o.size() > 3 else 1.0
		views.append([spot + Vector3(sin(ang) * float(o[0]), float(o[1]), cos(ang) * float(o[0])), spot + Vector3(0, aim, 0)])
	elif args.has("cam"):
		var parts := String(args["cam"]).split(";")
		var a := parts[0].split(",")
		var b := parts[1].split(",")
		views.append([Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(b[0]), float(b[1]), float(b[2]))])
	else:
		views = [[Vector3(0, 1.4, -6), Vector3(0, 1.2, 0)], [Vector3(0, 1.4, 6), Vector3(0, 1.2, 0)],
				[Vector3(-6, 1.4, 0), Vector3(0, 1.2, 0)], [Vector3(6, 1.4, 0), Vector3(0, 1.2, 0)],
				[Vector3(0, 60, 0.1), Vector3(0, 0, 0)]]
	if args.has("figure"):                               # --figure=res://content/characters/<name>/celt_animated.gltf
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(String(args["figure"]), state) == OK:
			var fig := doc.generate_scene(state) as Node3D
			add_child(fig)
			fig.position = spot
			var to_cam: Vector3 = views[0][0] - spot
			fig.rotation.y = atan2(to_cam.x, to_cam.z) + float(args.get("figure_turn", "0"))
			var players := fig.find_children("*", "AnimationPlayer", true, false)
			if players.size() > 0 and (players[0] as AnimationPlayer).has_animation("idle"):
				(players[0] as AnimationPlayer).play("idle")
	var prefix := String(args.get("out", "user://pregame"))
	for i in views.size():
		cam.global_position = views[i][0]
		cam.look_at(views[i][1])
		for f in 40:
			await get_tree().process_frame
			if f % 10 == 0:
				print("view ", i, " frame ", f, " ", Time.get_ticks_msec())
		get_viewport().get_texture().get_image().save_png("%s_%s_%d.png" % [prefix, realm, i])
		print("saved view ", i)
	get_tree().quit()
