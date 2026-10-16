extends Node
## Debug (owner 2026-10-14: no sound / effect when a necromancer's zombie appears; no battle music in attack mode;
## attack mode stays on when the target dies): on the running server with Claude's GM test account - attack mode on
## the nearest monster (battle music in), the monster killed by /mob kill (attack mode and music out), then the
## necromancer's Call Minor Zombie Servant (/cast spell 9401): the effect on the new servant (screenshots
## user://necro_<n>.png), then the servant released.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	var sw: ServerWorld
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind in ["spell_effect", "attack_mode", "cast"]:
			var tv = sw._view_of(int(d.get("target", -1))) if sw and d.has("target") else null
			print("[necro] packet ", kind, " ", str(d).left(160), "  target view now: ", tv != null))
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	sw = v.npcs
	Server.command("/jump to 335142 516409 4791 200")     # Lough Derg's wolves
	await _wait(14.0)
	# --- attack mode, battle music, the target dying
	var mob: Npc = null
	for st in sw.by_oid.values():
		var s: NpcState = st
		if s.view and s.alive and int(s.spawn.realm) == 0 and (mob == null or
				s.pos.distance_to(v.player.global_position) < mob.state.pos.distance_to(v.player.global_position)):
			mob = s.view
	if mob == null:
		print("[necro] no monster in view")
	else:
		print("[necro] target ", mob.spawn.name, " at ", mob.state.pos.distance_to(v.player.global_position), " m")
		sw.select(mob)
		await _wait(1.0)
		v._toggle_attack()
		await _wait(2.5)
		print("[necro] attack on: ", v._server_attack, "  battle music: ", _music())
		Server.command("/mob kill")
		await _wait(3.0)
		print("[necro] after the kill: attack on: ", v._server_attack, "  target alive: ",
				mob.state.alive if is_instance_valid(mob) else "freed", "  battle music: ", _music())
		sw.clear_target()
	# --- the necromancer's servant
	await _wait(2.0)
	for w in v.ui.windows.values():                       # (windows left open by earlier runs hide the servant)
		if w is Control:
			(w as Control).visible = false
	var before := sw.by_oid.keys()
	var live0 := SpellFx._live_count()
	var t0 := Time.get_ticks_msec()
	Server.command("/cast spell 9401")
	var pet: Npc = null
	for _i in 80:
		await _wait(0.1)
		for oid in sw.by_oid:
			var s: NpcState = sw.by_oid[oid]
			if not before.has(oid) and s.view:
				pet = s.view
		if pet:
			break
	print("[necro] servant view after ", Time.get_ticks_msec() - t0, " ms")
	for oid in sw.by_oid:
		if not before.has(oid):
			var s: NpcState = sw.by_oid[oid]
			print("[necro] new object ", oid, " ", s.spawn.name, " model ", s.spawn.get("model"), " info ", s.info.keys(),
					" view ", s.view != null, " at ", s.pos.distance_to(v.player.global_position), " m")
	await _wait(0.4)
	print("[necro] servant: ", pet.spawn.name if pet else "none", "  effects alive ", live0, " -> ", SpellFx._live_count())
	if pet:
		var fx := []
		for n in pet.find_children("*", "", true, false):
			if String(n.scene_file_path).contains("effects") or String(n.name).to_lower().contains("arawn"):
				fx.append(n.name)
		print("[necro] effect nodes on the servant: ", fx)
		var row: Dictionary = (v.player.sounds.index.get("spells", {}) as Dictionary).get("2", {})
		print("[necro] sound set 2 hit sound: ", row.get("hit", ""))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://necro_1.png")
	await _wait(1.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://necro_2.png")
	Server.client.call("PetCommand", 0, 0, 2)                # release the servant (the shade ends)
	await _wait(2.0)
	get_tree().quit()


func _music() -> String:
	var a = v.audio
	if a == null or a._battle == null:
		return "none"
	return "%s at %.0f dB" % ["playing" if a._battle.playing else "stopped", a._battle.volume_db]


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
