extends Node
## Debug, local (owner 2026-10-15: Mularn's Elizabeth <Smith>, model 1969 Half Ogre female, was invisible): the later
## races' models (--models, default Half Ogre f / m, Shar f / m, Svartalf f / m) stood in a row and pictured
## (user://race_models.png). Runs once, quits (hard stop 40 s).
func _ready() -> void:
	if get_tree().root.has_meta("race_models_ran"):
		return
	get_tree().root.set_meta("race_models_ran", true)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	v.ui.visible = false
	var ids := String(v.args.get("models", "1969,1968,1971,1970,1973,1972")).split(",")
	var pets: Pets = v.combat.pets
	var base: Vector3 = v.player.global_position + Vector3(0, 0, -5)
	var made := []
	for i in ids.size():
		var t := Pets.template(74).duplicate(true)
		t["models"] = [int(ids[i])]
		t["name"] = "model " + ids[i]
		t.erase("equipment")
		var at := base + Vector3((i - ids.size() / 2.0) * 1.6, 0, 0)
		at.y = v.npcs.ground_at(at)
		var st = pets._make(t, 40, at, {})
		st.yaw = 0.0
		made.append(st)
	for w in 30:
		if made.all(func(s): return s.view != null):
			break
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.0).timeout
	for st in made:
		print("[rm] %s: view %s" % [st.spawn.name, st.view != null])
	v.player.face(PI)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.global_position = base + Vector3(0, 1.4, 5.5)
	cam.look_at(base + Vector3(0, 1.0, 0))
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://race_models.png")
	get_tree().quit()
