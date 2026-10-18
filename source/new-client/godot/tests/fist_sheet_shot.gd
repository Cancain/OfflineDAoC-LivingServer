extends Node3D
## Debug (owner 2026-10-17: fist weapons' orientation): every hand-to-hand weapon model drawn in its grip frame as
## WeaponModels.make hangs it on a bone - the bone's +X (along the forearm, towards the fingers) to the RIGHT, +Y up -
## in a labelled grid: user://fist_sheet.png. Runs once.
const IDS := [959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, 972, 973, 974, 975, 976, 977, 978,
		979, 980, 981, 982, 3333, 3550, 3566, 3575, 3683, 3686, 3843, 3944, 4307, 4308, 4311, 4312]
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var cols := 6
	for i in IDS.size():
		var holder := Node3D.new()                       # NIF space (X right, Y up, Z to the camera), 40 units a cell
		holder.position = Vector3((i % cols) * 0.8 - 2.0, -(i / cols) * 0.8 + 2.0, 0)
		holder.scale = Vector3.ONE * 0.02
		add_child(holder)
		var w := WeaponModels.make(IDS[i], true, false)
		if w:
			holder.add_child(w)
		var l := Label3D.new()
		l.text = "%d %s" % [IDS[i], String(WeaponModels.info(IDS[i]).get("nif", "")).replace("n_hth_", "")]
		l.font_size = 40
		l.pixel_size = 0.002
		l.position = holder.position + Vector3(0, -0.3, 0)
		add_child(l)
		var axis := MeshInstance3D.new()                 # the forward axis (+X) as a red line
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.006, 0.006)
		axis.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		axis.material_override = mat
		axis.position = holder.position + Vector3(0.125, 0, 0)
		add_child(axis)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0
	cam.position = Vector3(0, 0, 10)
	add_child(cam)
	cam.make_current()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("user://fist_sheet.png")
	get_tree().quit()
