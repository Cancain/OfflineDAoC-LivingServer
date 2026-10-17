extends Node3D
## Visual test: loads one glTF at runtime, lights it on a simple stage, saves screenshots and quits.
##   Godot --path godot --screen 1 res://tests/render_model.tscn -- --gltf=<abs path> --out=<abs png prefix> [--yaw=0]
## Writes <out>_full.png (whole figure) and <out>_face.png (head and shoulders close-up); with --frame it writes
## one <out>_view.png framed on the model's bounds instead (for world objects, weapons, shields).

const SHOTS := [
	# name, camera position, look-at target, vertical fov
	["full", Vector3(0.0, 1.05, 3.2), Vector3(0.0, 0.92, 0.0), 38.0],
	["face", Vector3(0.0, 1.62, 0.78), Vector3(0.0, 1.58, 0.0), 32.0],
]


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	get_window().size = Vector2i(int(args.get("width", "720")), int(args.get("height", "960")))

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(args["gltf"], state)
	if err != OK:
		push_error("glTF load failed (%s): %s" % [err, args["gltf"]])
		get_tree().quit(1)
		return
	var model := doc.generate_scene(state) as Node3D
	model.rotation_degrees.y = float(args.get("yaw", "0"))
	add_child(model)
	for node in model.find_children("collision_*", "MeshInstance3D", true, false):
		node.visible = false                            # collision volumes from the NIF are physics-only
	_prepare_materials(model)
	var cam := _build_stage(not args.has("frame"))

	var shots := SHOTS
	if args.has("frame"):                             # any model: frame its bounds from the front-left
		var box := _bounds(model)
		var size := box.size.length()
		var centre := box.get_center()
		shots = [["view", centre + Vector3(-0.55, 0.35, 0.75).normalized() * size * 1.15, centre, 40.0]]
	for shot in shots:
		cam.position = shot[1]
		cam.fov = shot[3]
		cam.far = 4000.0
		cam.look_at(shot[2])
		for i in 10:                                  # let shadows, SSAO and mipmaps settle
			await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [args["out"], shot[0]]
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()


func _bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _prepare_materials(root: Node) -> void:
	# runtime-loaded glTF images arrive without mipmaps; build them so distant texels filter like an imported texture
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var img := mat.albedo_texture.get_image()
			if not img.has_mipmaps():
				img.generate_mipmaps()
			mat.albedo_texture = ImageTexture.create_from_image(img)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mat.roughness = 0.85


func _build_stage(with_ground := true) -> Camera3D:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.48, 0.66)
	sky_mat.sky_horizon_color = Color(0.70, 0.72, 0.70)
	sky_mat.ground_horizon_color = Color(0.45, 0.42, 0.36)
	sky_mat.ground_bottom_color = Color(0.20, 0.18, 0.15)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 32.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.26, 0.30, 0.20)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	if with_ground:
		add_child(ground)

	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	return cam
