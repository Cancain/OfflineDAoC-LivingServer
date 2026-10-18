extends SceneTree
## Debug: compiles NifMaterials' shader variants on the real renderer and draws one frame - a shader mistake prints
## "SHADER ERROR" here instead of breaking every model in game. Runs ~2 s.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var nm := NifMaterials.new({"x": "x"}, "x")
	var y := 0.0
	for a in ["opaque", "blend", "clip"]:
		for ds in [false, true]:
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			var m := ShaderMaterial.new()
			m.shader = nm._shader(a, ds)
			m.set_shader_parameter("has_env", true)
			m.set_shader_parameter("has_gloss", true)
			mi.material_override = m
			mi.position = Vector3(0, y, -5)
			y += 0.1
			root.add_child(mi)
	var cam := Camera3D.new()
	root.add_child(cam)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("[shader] drawn")
	quit()
