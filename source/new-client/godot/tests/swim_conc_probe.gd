extends Node
## Debug (owner 2026-10-14: combat while swimming as the original; companion bots stood on top of the water; logging
## in with concentration buffs set every effect and sound off at once). On a test server run:
##   --phase=a  a self buff (the first spell of the first line), then into deep water (GM /jump): a swing and a cast
##              there (the clip each plays, user://swimconc_<n>.png), a nearby NPC put in the water (NpcState.swimming,
##              its height, its clip), then a proper /quit (the server saves the buff)
##   --phase=b  logging back in: the server's restored buff effects (each packet, ms after PlayerInit) and how many
##              effects / sounds the client shows in the first seconds
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	Server.world.connect(func(k: String, d: Dictionary):
		if k == "spell_effect":
			print("[sc] %+d ms after PlayerInit: spell effect %d, caster %d -> target %d (me %d)" % [
					Time.get_ticks_msec() - Server.init_at, int(d.spell), int(d.caster), int(d.target), Server.me_oid]))
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	if String(v.args.get("phase", "a")) == "b":
		for i in 4:
			await _wait(1.0)
			print("[sc] %.1f s after PlayerInit: %d spell effects showing, %d sounds playing" % [
					(Time.get_ticks_msec() - Server.init_at) / 1000.0, SpellFx._live.size(), _sounds_playing()])
		print("[sc] effects on me: ", Server.effects.values().map(func(e): return e.get("name", "?")))
		get_tree().quit()
		return
	await _wait(8.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	print("[sc] first line: ", Server.spell_lines[0].name if not Server.spell_lines.is_empty() else "-")
	Server.use("srv:spell:0:1")
	await _wait(5.0)
	print("[sc] effects on me: ", Server.effects.values().map(func(e): return e.get("name", "?")))
	var spot := _deep_water()
	if spot == Vector3.INF:                                  # none near: Lough Derg's lake (zone 200, region 200)
		var lake: Vector3 = Server.to_region(200, Vector3(1238.4, 115.325, 1430.4))
		Server.command("/jump to %d %d %d 200" % [roundi(lake.x), roundi(lake.y), roundi(lake.z)])
		await _wait(15.0)
		spot = _deep_water()
	print("[sc] deep water at ", spot, " water ", v.npcs._water_at(spot), " bed ", v.npcs._grid_at(spot))
	if spot == Vector3.INF:
		Server.quit_world(true)
		return
	var zid := int(v.region.current.info.id) if v.region and v.region.current else int(v.zone.info.id)
	var r: Vector3 = Server.to_region(zid, spot)
	Server.command("/jump to %d %d %d" % [roundi(r.x), roundi(r.y), roundi(r.z)])
	await _wait(5.0)
	var p: Node3D = v.player
	print("[sc] after the jump: swimming %s  y %.2f  water %.2f" % [v.player.swimming, p.global_position.y,
			v.npcs._water_at(p.global_position)])
	v.player.face(v.player.facing() + PI)
	await _wait(0.5)
	var clip: String = v.player.swing(v.player.weapon_stance())
	await _wait(0.2)
	print("[sc] a swing in the water: %s - playing %s" % [clip, v.player._anim.current_animation])
	await _shot(0)
	await _wait(2.0)
	Server.use("srv:spell:0:1")
	await _wait(0.6)
	print("[sc] a cast in the water: casting %s - playing %s" % [v.player.casting_spell, v.player._anim.current_animation])
	await _shot(1)
	await _wait(4.0)
	print("[sc] after the cast: playing %s" % v.player._anim.current_animation)
	# a nearby NPC with a race figure, put where the server would hold a swimmer (the surface, flagged underwater)
	var best: NpcState = null
	for st in v.npcs.states:
		if st.view and is_instance_valid(st.view) and (st.view as Npc).model is Fig3Figure and st.alive:
			if best == null or st.pos.distance_to(p.global_position) < best.pos.distance_to(p.global_position):
				best = st
	if best:
		var w: float = v.npcs._water_at(spot)
		best.pos = Vector3(spot.x + 2.0, w, spot.z + 2.0)
		var mv: Dictionary = v.npcs._mover.get(best, {})
		mv["water"] = true
		v.npcs._mover[best] = mv
		v.npcs._ground(best)
		await _wait(0.5)
		var n := best.view as Npc
		print("[sc] NPC %s in the water: swimming %s  y %.2f (water %.2f)  playing %s" % [best.spawn.get("name", "?"),
				best.swimming, best.pos.y, w, n.anim.current_animation if n.anim else "-"])
		await _shot(2)
	Server.quit_world(true)


## The deepest-enough water nearest you (more than 3 m over its bed), searched in rings out to 600 m.
func _deep_water() -> Vector3:
	var p: Vector3 = v.player.global_position
	for ring in range(1, 61):
		var rad := ring * 10.0
		for k in 36:
			var a := k * TAU / 36.0
			var q := p + Vector3(cos(a), 0.0, sin(a)) * rad
			var w: float = v.npcs._water_at(q)
			if w > -INF and w - v.npcs._grid_at(q) > 3.0:
				return Vector3(q.x, w, q.z)
	return Vector3.INF


func _sounds_playing() -> int:
	var n := 0
	for a in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if (a as AudioStreamPlayer3D).playing:
			n += 1
	return n


func _shot(n: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://swimconc_%d.png" % n)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
