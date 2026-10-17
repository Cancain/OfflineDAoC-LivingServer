extends Node
## Debug (owner 2026-10-10, bot plan phase 1: NPC click boxes too small vs the old client; names should be clickable):
## for the NPCs near the camera, click points the old thin capsule missed - the model's side edge and shoulder - and
## the middle of the overhead name, and report what NpcManager.pick returns.
##   --screen 1 --skip-login --zone=202 --figure=cel_m --probe=click_pick_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var npcs: NpcManager = v.npcs
	var tried := 0
	var ok := {"edge": 0, "shoulder": 0, "name": 0}
	for i in npcs.active.keys():
		var n: Npc = npcs.active.get(i)
		if not is_instance_valid(n) or n._pick == null:
			continue
		var anchor := n.global_position + Vector3(0, n.height * 0.5, 0)
		var front := n.global_transform.basis.z.normalized()
		v.player.global_position = n.global_position + front * 3.0         # near enough for its name to show
		v.player.hold()
		cam.global_position = anchor + front * maxf(5.0, n.height * 3.0) + Vector3(0, 0.5, 0)
		cam.look_at(anchor)
		for f in 3:
			await get_tree().process_frame
		var box := ((n._pick.get_child(0) as CollisionShape3D).shape as BoxShape3D)
		var right := cam.global_transform.basis.x
		var mid := cam.unproject_position(anchor)
		var edge := cam.unproject_position(anchor + right * (box.size.x * 0.45))
		var shoulder := cam.unproject_position(n.global_position + Vector3(0, n.height * 0.85, 0) + right * (box.size.x * 0.3))
		if not get_viewport().get_visible_rect().has_point(mid):
			continue
		tried += 1
		var res := {}
		for k in [["edge", edge], ["shoulder", shoulder]]:
			res[k[0]] = npcs.pick(cam, k[1]) == n
			if res[k[0]]:
				ok[k[0]] += 1
		var labels: Array = n.get_meta("plate", [])
		if bool(n.get_meta("plate_shown", false)) and not labels.is_empty():
			var p := cam.unproject_position((labels[0] as Label3D).global_position) - Vector2(0, (labels[0] as Label3D).font_size * 0.5 + (labels[0] as Label3D).offset.y)
			res["name"] = npcs.pick(cam, p) == n
			if res["name"]:
				ok["name"] += 1
		print("[click] %-24s height %.2f box %s capsule radius was %.2f -> %s" % [String(n.spawn.name), n.height,
				box.size.snapped(Vector3.ONE * 0.01), clampf(n.height * 0.25, 0.25, 2.5), res])
		if tried >= 12:
			break
	print("[click] %d NPCs: side edge %d, shoulder %d, name %d" % [tried, ok.edge, ok.shoulder, ok.name])
	get_tree().quit()
