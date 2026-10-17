extends SceneTree
## Debug (windowed): does a GPUParticles3D node's scale reach world-space particles (size and speed)? Three
## identical systems seen from above by an orthographic camera: node scale 1, node scale 0.25, and a parent at 0.25.
##   Godot --screen 1 --path godot --script res://tests/particle_scale_main.gd -- --out=<png>


func _sys(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.local_coords = false
	p.amount = 64
	p.lifetime = 1.0
	p.position = at
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.RIGHT
	pm.spread = 0.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 4.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	return p


func _initialize() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.position = Vector3(4, 20, 0)
	cam.rotation = Vector3(-PI / 2, 0, 0)
	root3.add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	root3.add_child(env)
	var a := _sys(Vector3(0, 0, -5))
	root3.add_child(a)
	var b := _sys(Vector3(0, 0, 0))
	b.scale = Vector3.ONE * 0.25
	root3.add_child(b)
	var par := Node3D.new()
	par.position = Vector3(0, 0, 5)
	par.scale = Vector3.ONE * 0.25
	root3.add_child(par)
	par.add_child(_sys(Vector3.ZERO))
	await create_timer(2.0).timeout
	var out := ""
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.substr(6)
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
