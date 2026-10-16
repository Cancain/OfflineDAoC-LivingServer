extends Node
## Debug (owner 2026-10-14: "make sure animist shrooms and other ground targeting and keybindings work"): with Claude's
## Animist test character on the running server (server_session.tscn --char=Claudeanim --race=Firbolg --class=55):
## level 50 (GM), the Ground Target key's path (ground under a screen point -> PlayerGroundTarget), /gtrange, then the
## highest fire-and-forget turret (SummonAnimistFnF) and the main shroom cast - the shrooms must appear where aimed.
var v: Node
var lines: Array = []


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k = ""): lines.append(String(t)); print("[gt] message: ", t))
	await _wait(8.0)
	Server.command("/player level 50")
	await _wait(6.0)
	Server.command("/train Arboreal Path 35")                   # the shroom lines (Arboreal Mastery: Tanglers, the
	await _wait(2.0)                                             # Forest's pets; Verdant Path: the spore turrets)
	Server.command("/train Verdant Path 20")
	await _wait(4.0)
	# the Ground Target key: the ground under the screen 12 m ahead of the camera
	var cam: Camera3D = v.player.camera
	var ahead: Vector3 = v.player.global_position + (-v.player.global_transform.basis.z).normalized() * 12.0
	ahead.y = (v.npcs as ServerWorld).ground_at(Vector3(ahead.x, ahead.y + 20.0, ahead.z))
	var screen := cam.unproject_position(ahead + Vector3(0, 0.05, 0))
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 250.0,
			ZoneLoader.LAYER_FLOOR | ZoneLoader.LAYER_WALL)
	var hit: Dictionary = v.get_world_3d().direct_space_state.intersect_ray(q)
	var zid: int = (v.npcs as ServerWorld)._current_zone()
	print("[gt] player region ", Server.to_region(zid, v.player.global_position), "  hit ", hit.get("position"),
			" region ", Server.to_region(zid, hit.get("position", Vector3.ZERO)), "  zone ", zid)
	Server.command("/loc")
	var feet := Server.to_region(zid, v.player.global_position)              # 1. your own feet: on the mesh
	Server.client.call("GroundTarget", int(feet.x), int(feet.y), int(feet.z), 0x100)
	await _wait(1.0)
	Server.command("/gtrange")
	await _wait(1.5)
	print("[gt] all spells: ", Server.spell_lines.map(func(l): return [String(l.name), (l.spells as Array).map(func(x): return "%s %s" % [x.level, x.name])]))
	var near: Vector3 = v.player.global_position + (-v.player.global_transform.basis.z).normalized() * 3.0
	near.y = (v.npcs as ServerWorld).ground_at(Vector3(near.x, near.y + 5.0, near.z))
	v._server_ground_target(cam.unproject_position(near))                    # 2. the key's path, 3 m ahead
	await _wait(1.5)
	Server.command("/gtrange")
	await _wait(2.0)
	# the turret spells this Animist has
	var turret := ""
	var main_pet := ""
	for li in Server.spell_lines.size():
		for sp in Server.spell_lines[li].spells:
			var nm := String(sp.name)
			if String(sp.get("kind", "")) != "" and false:
				pass
			if nm.contains("Tangler") or nm.contains("Sporespawn"):
				turret = "srv:spell:%d:%d" % [li, int(sp.level)]
				print("[gt] turret spell: ", nm, " ", turret)
			if nm in ["Forest's Servant", "Forest's Companion", "Forest's Compatriot", "Forest's Aid", "Forest's Sentry", "Forest's Bulwark", "Forest's Protector"]:
				main_pet = "srv:spell:%d:%d" % [li, int(sp.level)]
	print("[gt] spell lines: ", Server.spell_lines.map(func(l): return String(l.name)))
	var before := _shrooms()
	# as a player casts them: the shroom spells in the usable skills (Animist spec spells come as skills, page 3)
	var picks := {}
	for i in Server.skills.size():
		var nm := String(Server.skills[i].name)
		if nm.contains("Tangler") or nm in ["Forest's Servant", "Forest's Companion", "Forest's Compatriot", "Forest's Aid", "Forest's Sentry", "Forest's Bulwark", "Forest's Protector"]:
			picks[nm.left(8)] = ["srv:skill:%d" % i, nm]
	print("[gt] shroom skills: ", picks.values())
	print("[gt] skills: ", Server.skills.map(func(x): return "%s:%s:%s" % [x.page, x.level, x.name]))
	for k in picks:
		print("[gt] casting ", picks[k][1], " -> ", Server.use(String(picks[k][0])))
		await _wait(6.0)
	print("[gt] after the player casts: ", _shrooms())
	if turret != "":
		Server.use(turret)
		await _wait(6.0)
	if main_pet != "":
		Server.use(main_pet)
		await _wait(8.0)
	var after := _shrooms()
	print("[gt] mushrooms near the ground target: before ", before.size(), " after ", after.size(), " ", after)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ground_probe.png")
	get_tree().quit()


func _shrooms() -> Array:
	var out := []
	for st in (v.npcs as ServerWorld).by_oid.values():
		var s: NpcState = st
		if String(s.spawn.get("model", "")) == "860":
			out.append([s.spawn.name, s.pos.distance_to(v.player.global_position), s.view != null])
	return out


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
