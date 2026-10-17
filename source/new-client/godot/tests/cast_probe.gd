extends Node
## Debug: the spell system. A test Eldritch casts its spells at a nearby monster and on itself; the chat is printed.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=cast_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	PlayerData.level = 10
	PlayerData.promote(40)                                   # Eldritch
	for k in PlayerData.specs:
		PlayerData.specs[k] = 8
	PlayerData.skills_changed.emit()
	PlayerData.set_power(999)
	print("[cast] power ", PlayerData.power_pts, "/", PlayerData.max_power, " lines:")
	var spells := []
	for line in ClassDb.spell_lines(PlayerData.class_id(), PlayerData.level, PlayerData.specs):
		print("   ", line.name, " ", (line.spells as Array).map(func(s): return ClassDb.spell(int(s)).get("name", s)))
		spells.append_array(line.spells)
	var npcs: NpcManager = viewer.npcs
	var best: NpcState = null
	for st in npcs.states:
		var s: NpcState = st
		if int(s.spawn.realm) == 0 and s.alive and s.level <= 3 and (best == null or s.pos.distance_to(viewer.player.global_position) < best.pos.distance_to(viewer.player.global_position)):
			best = s
	var at: Vector3 = best.pos + Vector3(14, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.2
	viewer.player.global_position = at
	viewer.player.face(atan2(-(best.pos.x - at.x), -(best.pos.z - at.z)))
	await get_tree().create_timer(1.0).timeout
	if best.view:
		npcs.select(best.view)
	var cast: Casting = viewer.combat.casting
	var tried := 0
	for sid in spells:
		var sp := ClassDb.spell(int(sid))
		if tried >= 6:
			break
		tried += 1
		print("[cast] using ", sp.get("name"), " (", sp.get("type"), ", ", sp.get("target"), ", ", sp.get("casttime"), " s)")
		PlayerData.use_skill.emit({"kind": "spell", "id": str(sid)})
		await get_tree().create_timer(float(sp.get("casttime", 0)) + 1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/cast_%d.png" % [String(viewer.args.get("out", "user://cast")), tried])
	print("[cast] effects on player ", cast.player_effects().size(), " monster hp ", best.hp, "/", best.max_hp, " alive ", best.alive)
	get_tree().quit()
