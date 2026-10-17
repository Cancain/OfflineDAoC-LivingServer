extends Node
## Debug (owner 2026-10-14: tendrils / stranglers - vine effects on the invisible body, model 667 - and the animated
## weapons of Trollheim / Mithra's tomb - floating weapons on it): on a test server run, Claude's GM test character
## goes to a tendril (Aegirhamn, region 151) and then an animate svard (region 150) - the view, its weapons, the vine
## effects the server sends; screenshots user://invisible_<n>.png; then the window closes itself.
var v: Node
var _fx := {}


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(8.0)
	var stops := [["tendril", "/jump to 273718 350838 4464 151"], ["animate svard", "/jump to 38900 46193 15604 150"]]
	for i in stops.size():
		Server.command(stops[i][1])
		await _wait(16.0)
		v = get_tree().current_scene
		var sw: ServerWorld = v.npcs
		_fx.clear()
		Server.world.connect(_count)
		var mob: NpcState = null
		for st in sw.by_oid.values():
			var s: NpcState = st
			if String(s.spawn.name) == stops[i][0] and (mob == null or
					s.pos.distance_to(v.player.global_position) < mob.pos.distance_to(v.player.global_position)):
				mob = s
		if mob == null:
			print("[inv] no %s in view" % stops[i][0])
			Server.world.disconnect(_count)
			continue
		var n: Npc = mob.view
		print("[inv] %s model %s at %.0f m  view %s" % [mob.spawn.name, mob.spawn.get("model"), mob.pos.distance_to(v.player.global_position), n != null])
		if n:
			v.player.face(atan2(-(n.global_position.x - v.player.global_position.x), -(n.global_position.z - v.player.global_position.z)))
			var weapons := n._weapon_nodes.filter(func(w): return is_instance_valid(w))
			print("[inv]   weapons hung: %d  slots %s" % [weapons.size(), n._weapon_slots])
		await _wait(7.0)
		print("[inv]   spell effects seen on it in 7 s: ", _fx.get(int(mob.spawn.get("oid", -1)), _fx))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://invisible_%d.png" % i)
		Server.world.disconnect(_count)
	get_tree().quit()


func _count(kind: String, d: Dictionary) -> void:
	if kind == "spell_effect":
		var k := "%d:%d" % [int(d.target), int(d.spell)]
		_fx[k] = int(_fx.get(k, 0)) + 1


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
