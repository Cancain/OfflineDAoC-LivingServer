extends Node
## Debug, local (owner 2026-10-15: the bonedancer commander's arms - "weird empty space" at the elbows): monster
## models (--models, default 952) in a row, idle, pictured from the front (user://bd_commander_<tag>.png, --tag).
## Runs once, quits (hard stop 50 s).
func _ready() -> void:
	if get_tree().root.has_meta("bd_commander_ran"):
		return
	get_tree().root.set_meta("bd_commander_ran", true)
	get_tree().create_timer(50.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	v.player.visible = false
	var pets: Pets = v.combat.pets
	var ids := String(v.args.get("models", "952")).split(",")
	var base: Vector3 = v.player.global_position + Vector3(0, 0, -2)
	var made := []
	for i in ids.size():
		var t := Pets.template(74).duplicate(true)
		t["models"] = [int(ids[i])]
		t["name"] = ids[i]
		t.erase("equipment")
		var at := base + Vector3((i - (ids.size() - 1) / 2.0) * 2.2, 0, 0)
		at.y = v.npcs.ground_at(at)
		var st = pets._make(t, 40, at, {})
		st.yaw = 0.0
		made.append(st)
	for w in 40:
		if made.all(func(s): return s.view != null):
			break
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.5).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.global_position = base + Vector3(0, 1.4, 1.2 + ids.size() * 1.4)
	cam.look_at(base + Vector3(0, 0.9, 0))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://bd_commander_%s.png" % String(v.args.get("tag", "x")))
	get_tree().quit()
