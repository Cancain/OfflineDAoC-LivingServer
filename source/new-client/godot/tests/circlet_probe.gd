extends Node
## Debug, local (owner 2026-10-14: circlets, which show the hair, hide it): your figure's head close up with no helm,
## then the helm models the server's circlets use (1292 crafted circlet, 826 / 827 / 840 named circlets), what the hair
## does under each (visible, its helm morph) - user://circlet_<model>.png. Runs once, quits itself.
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_f --ui-test --probe=circlet_probe
func _ready() -> void:
	if get_tree().root.has_meta("circlet_probe_ran"):
		return
	get_tree().root.set_meta("circlet_probe_ran", true)
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())   # hard limit
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.ui.visible = false
	var p: Node3D = v.player
	var fig: Fig3Figure = p.get("_model")
	var head := p.global_position + Vector3(0, 1.55, 0)
	var cam := Camera3D.new()
	p.get_parent().add_child(cam)
	cam.global_position = head + p.global_basis.z * -1.1 + p.global_basis.x * 0.4 + Vector3(0, 0.15, 0)
	cam.look_at(head, Vector3.UP)
	cam.current = true
	cam.fov = 40.0
	for model in [0, 1292, 826, 827, 840]:
		fig.set_helm(model, false, 0)
		await get_tree().create_timer(0.6).timeout
		var hair := []
		for st in fig.meta.get("hair_styles", []):
			if st.node and fig._meshes.has(st.node):
				for mi in fig._parts(st.node):
					if (mi as MeshInstance3D).visible:
						hair.append(String(st.node))
		var e: Dictionary = Fig3Figure._helms.get(str(model), {}).get(String(fig.meta.get("prefix", "")), {})
		print("[circ] helm %d: %s  hair type %s  hair drawn %s" % [model, String(e.get("file", "-")).get_base_dir(),
				e.get("hair", "-"), hair])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://circlet_%d.png" % model)
	# the crafted circlet with each of the hair's helm morphs forced: none, 1, 2, 3
	fig.set_helm(1292, false, 0)
	for k in [0, 1, 2, 3]:
		fig._helm_hair = k
		fig._refresh_hair()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://circlet_morph_%d.png" % k)
	get_tree().quit()
