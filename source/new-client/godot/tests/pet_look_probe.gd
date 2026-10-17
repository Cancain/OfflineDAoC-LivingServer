extends Node
## Debug (owner 2026-10-10: period pet looks): each pet template in --tids (default: a commander, every Bonedancer minion
## kind, every Necromancer pet) stood in a row and photographed from a 3/4 front view.
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=pet_look_probe --out=<dir>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var pets: Pets = viewer.combat.pets
	var ids := String(viewer.args.get("tids", "51,52,65,71,77,83,53,59,200,203,204,205,206")).split(",")
	var base: Vector3 = viewer.player.global_position + Vector3(0, 0, -6)
	var made := []
	for i in ids.size():
		var t := Pets.template(int(ids[i]))
		var at := base + Vector3(i * 3.0, 0, 0)
		at.y = viewer.npcs.ground_at(at)
		var st := pets._make(t, 40, at, {})
		st.yaw = 0.0
		made.append(st)
	await get_tree().create_timer(6.0).timeout
	for st in made:
		print("[look] view ", st.spawn.name, " ", st.view != null, " alive ", st.alive, " at ", st.pos.snapped(Vector3.ONE * 0.1),
				" player ", viewer.player.global_position.snapped(Vector3.ONE * 0.1))
	var cam := Camera3D.new()
	viewer.add_child(cam)
	cam.current = true
	for i in made.size():
		var st: NpcState = made[i]
		var h: float = float(st.view.get("height")) if st.view and st.view.get("height") != null else 2.0
		cam.global_position = st.pos + Vector3(1.6, h * 0.8, 2.6) * maxf(1.0, h / 1.8)
		cam.look_at(st.pos + Vector3(0, h * 0.5, 0))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pet_%s.png" % [String(viewer.args.get("out", "user://")), ids[i]])
		print("[look] ", ids[i], " ", st.spawn.name, " model ", st.spawn.model, " eq ", viewer.npcs.data.get("equipment", {}).get(String(st.spawn.equipment), []).map(func(r): return [r.slot, r.model]))
	get_tree().quit()
