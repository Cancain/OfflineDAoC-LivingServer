extends Node
## Debug (owner 2026-10-14: keep doors, siege weapons, relics and the war map in the new client): with Claude's GM test
## account on the running server (tests/server_session.tscn), checks each piece and logs what the server sent:
##   1. a Hadrian's Wall keep door (15000101): its zone door got the id, the server's door object is known, clicking
##      it targets it and asks the server (DoorRequest -> DoorState)
##   2. a siege catapult (/siegeweapon create): drawn with its object model; using it opens the siege window
##   3. the war map: the server's keeps arrive (WarMapClaimedKeeps)
##   4. a relic (Albion strength relic, Castle Excalibur): drawn with its model
## Screenshots: user://keep_probe_<n>.png
var v: Node
var seen := {}


func _ready() -> void:
	v = get_tree().current_scene
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind in ["door_state", "siege_window", "siege_close", "siege_anim", "warmap_keeps", "warmap_fights"]:
			seen[kind] = int(seen.get(kind, 0)) + 1
			if kind != "warmap_fights":
				print("[keep] packet ", kind, " ", _short(d)))
	await _wait(8.0)
	var sw: ServerWorld = v.npcs
	# --- 1. keep door
	Server.command("/jump to 654300 293500 4870 1")
	await _wait(12.0)
	var door: ZoneDoor = _door(15000101)
	print("[keep] zone door 15000101 found: ", door != null, "  server door object: ", sw.doors.has(15000101),
			"  server doors known here: ", sw.doors.size())
	_shot(1)
	if door:
		sw.request_door(door)
		await _wait(3.0)
		print("[keep] after the click: targeted door oid ", sw.target_door, "  target window: ", PlayerData.target,
				"  door open: ", door.is_open, "  server driven: ", door.server_driven)
	# --- 2. siege weapon
	Server.command("/siegeweapon create catapult")
	await _wait(4.0)
	var siege: NpcState = null
	for st in sw.by_oid.values():
		if (st as NpcState).info.has("object_model"):
			siege = st
	print("[keep] siege weapon in the world: ", siege != null, "  ", (siege.spawn.name + " model " + str(siege.info.object_model)) if siege else "")
	if siege:
		for _i in 10:
			if siege.view:
				break
			await _wait(1.0)
		print("[keep] its view: ", siege.view != null, "  distance m: ", siege.pos.distance_to(v.player.global_position),
				"  still to load: ", sw._prep_needs(siege).keys(), "  info: ", siege.info)
		_shot(2)
		if siege.view:
			sw.select(siege.view)
			sw.interact(siege.view)
			await _wait(3.0)
			print("[keep] siege window open: ", v.ui.siege != null and v.ui.siege.visible)
			_shot(3)
			Server.client.call("SiegeCommand", 8, 0)            # release
			await _wait(2.0)
	# --- 3. war map
	v.ui.warmap.show_window()
	await _wait(3.0)
	print("[keep] war map live keeps: ", v.ui.warmap.live.size(), "  relic holders: ", v.ui.warmap.relic_holders)
	_shot(4)
	v.ui.warmap.hide_window()
	# --- 4. relic
	Server.command("/jump to 506400 308600 7700 1")
	await _wait(12.0)
	var relics := []
	for oid in sw.objects:
		var o: Node3D = sw.objects[oid]
		if is_instance_valid(o) and int(o.get_meta("model", 0)) in ServerWorld.RELIC_MODELS:
			relics.append([oid, o.get_meta("name", ""), o.get_meta("model")])
	print("[keep] relics drawn here: ", relics)
	_shot(5)
	if relics.size() > 0:                                       # use it: the server answers (pad rules) - the path works
		PlayerData.message.connect(func(t, k = ""): print("[keep] message: ", t))
		var r := Server.to_region(sw._current_zone(), v.player.global_position)
		Server.client.call("Target", int(relics[0][0]), 0x8000 | 0x6000)
		Server.client.call("Interact", int(relics[0][0]), int(r.x), int(r.y))
		await _wait(3.0)
	print("[keep] packets seen: ", seen)
	get_tree().quit()


func _door(id: int) -> ZoneDoor:
	var loaders: Array = v.region.zones.values() if v.get("region") and v.region else [v.zone]
	for zl in loaders:
		if zl and (zl as ZoneLoader).door_by_id.has(id):
			return (zl.door_by_id[id] as Array)[0]
	return null


func _short(d: Dictionary) -> String:
	var s := str(d)
	return s.left(260)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout


func _shot(n: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://keep_probe_%d.png" % n)
