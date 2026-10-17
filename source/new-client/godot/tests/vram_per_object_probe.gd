extends Node
## Debug (owner 2026-10-10: low framerate after loading): texture memory added by 10 of each thing an NPC view
## makes - race figures, dressed figures, monster models, weapons - to find what costs ~24 MB per NPC.
##   --screen 1 --skip-login --zone=26 --realm=alb --figure=bri_m --ui-test --no-npcs --probe=vram_per_object_probe


func _mem() -> float:
	return Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0


func _step(label: String, make: Callable) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var m0 := _mem()
	var t0 := Time.get_ticks_msec()
	var holder := Node3D.new()
	get_tree().current_scene.add_child(holder)
	for i in 10:
		var n: Node3D = make.call(i)
		if n:
			holder.add_child(n)
			n.position = Vector3(i * 2.0, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("[vram] %-28s +%7.1f MB for 10 (%d ms)" % [label, _mem() - m0, Time.get_ticks_msec() - t0])


func _ready() -> void:
	await get_tree().create_timer(4.0).timeout
	print("[vram] start %.1f MB" % _mem())
	await _step("figure cel_m x10 (same)", func(_i):
		var f := Fig3Figure.new()
		f.load_figure("cel_m")
		return f)
	await _step("figure cel_m x10 AGAIN", func(_i):
		var f := Fig3Figure.new()
		f.load_figure("cel_m")
		return f)
	print("[vram] cached figure textures: ", Fig3Figure._tex_cache.size())
	await _step("cel_m scene only x10", func(_i): return (Fig3Figure._scenes["cel_m"] as PackedScene).instantiate())
	await _step("cel_m scene, no anim x10", func(_i):
		var m := (Fig3Figure._scenes["cel_m"] as PackedScene).instantiate() as Node3D
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			ap.free()
		return m)
	await _step("cel_m meshes only x10", func(_i):
		var m := (Fig3Figure._scenes["cel_m"] as PackedScene).instantiate() as Node3D
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			ap.free()
		for sk in m.find_children("*", "MeshInstance3D", true, false):
			(sk as MeshInstance3D).skeleton = NodePath()
		return m)
	await _step("figure bri_f x10 (same)", func(_i):
		var f := Fig3Figure.new()
		f.load_figure("bri_f")
		return f)
	var npcs = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zone026/npcs.json"))
	var eq: Dictionary = npcs.get("equipment", {})
	var keys := eq.keys()
	await _step("dressed figures x10", func(i):
		var f := Fig3Figure.new()
		f.load_figure("bri_m")
		var parts := {}
		for e in eq[keys[i % keys.size()]]:
			if int(e.slot) in [22, 23, 25, 27, 28]:
				parts.merge(Fig3Figure.armor_parts(int(e.model), false), true)
		f.set_armor(parts)
		return f)
	await _step("weapon 59 x10 (same)", func(_i): return WeaponModels.make(59))
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var paths := []
	for k in mons:
		if mons[k] is Dictionary and mons[k].has("gltf") and paths.size() < 10:
			paths.append(String(mons[k].gltf))
	var mgr := NpcManager.new()
	await _step("monster model 1 x10 (same)", func(_i): return mgr.instance_model(paths[0]))
	await _step("monster models x10 (different)", func(i): return mgr.instance_model(paths[i]))
	get_tree().quit()
