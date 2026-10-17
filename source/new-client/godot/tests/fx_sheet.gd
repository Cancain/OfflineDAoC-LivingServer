extends Node
## Debug: a list of spell effect pieces (speffects ids) played one at a time on your character, each screenshotted at
## a few moments (user://fxsheet_<id>_<n>.png). --fx=1,2,3
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=elf_m --ui-test --probe=fx_sheet --fx=...
##   [--times=0.1,0.5,1.2]  seconds after the start to shoot (default 0.35, 1.1, 2.25)
func _ready() -> void:
	var v := get_tree().current_scene
	var ids := []
	var times := [0.35, 1.1, 2.25]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fx="):
			for x in a.get_slice("=", 1).split(","):
				ids.append(int(x))
		elif a.begins_with("--times="):
			times = []
			for x in a.get_slice("=", 1).split(","):
				times.append(float(x))
	await get_tree().create_timer(5.0).timeout
	v.ui.visible = false
	for id in ids:
		var node: Node3D = SpellFx.play(id, v.player, 1.8)
		var t := 0.0
		for k in times.size():
			await get_tree().create_timer(maxf(float(times[k]) - t, 0.0)).timeout
			t = float(times[k])
			get_viewport().get_texture().get_image().save_png("user://fxsheet_%d_%d.png" % [id, k])
			if OS.get_cmdline_user_args().has("--fx-debug") and node and is_instance_valid(node):
				for mi in node.find_children("*", "MeshInstance3D", true, false):
					var g := mi as MeshInstance3D
					var mat = g.get_surface_override_material(0) if g.get_surface_override_material_count() > 0 else null
					if mat == null and g.mesh:
						mat = g.mesh.surface_get_material(0)
					var op = mat.get_shader_parameter("opacity") if mat is ShaderMaterial else -1
					print("[fxdbg] ", id, " t=", times[k], " ", g.name, " vis ", g.is_visible_in_tree(), " at ", g.global_position.snappedf(0.01),
							" size ", (g.global_transform.basis * g.get_aabb().size).snappedf(0.01), " opacity ", op,
							" parent ", g.get_parent().name)
		if node and is_instance_valid(node):
			SpellFx.release(node)
		await get_tree().create_timer(0.6).timeout
	get_tree().quit()
