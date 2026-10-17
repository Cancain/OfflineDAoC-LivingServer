extends Node
## Debug (owner 2026-10-14: a damage over time's ticks made the caster swing; the concentration window; /quit and the
## ESC menu's QUIT): on the running server with Claude's GM test character in Lough Derg - Fungal Dilapidation on the
## nearest wolf (/cast spell 23001): every spell-damage blow from you and what you play then; Augmented Blow
## (concentration) and the window's list; then /quit (a GM: at once, saved, the character screen) - or with --esc the
## ESC menu's QUIT (saved, then the game closes by itself).
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	var esc := OS.get_cmdline_user_args().has("--esc")
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	var sw: ServerWorld = v.npcs
	if esc:
		print("[quit] ESC menu QUIT pressed")
		v.ui.options._quit_game()
		await _wait(15.0)
		print("[quit] still running after 15 s")
		get_tree().quit()
		return
	Server.command("/jump to 335142 516409 4791 200")
	await _wait(14.0)
	v = get_tree().current_scene
	sw = v.npcs
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind == "combat" and int(d.attacker) == Server.me_oid:
			await get_tree().process_frame
			var a = v.player.get("_anim")
			print("[dot] blow from you: result 0x%02X  you play: %s" % [int(d.result), a.current_animation if a else "?"]))
	var wolf: NpcState = null
	for st in sw.by_oid.values():
		var s: NpcState = st
		if s.view and s.alive and int(s.spawn.realm) == 0 and (wolf == null or
				s.pos.distance_to(v.player.global_position) < wolf.pos.distance_to(v.player.global_position)):
			wolf = s
	if wolf:
		print("[dot] target ", wolf.spawn.name, " at ", wolf.pos.distance_to(v.player.global_position), " m")
		sw.select(wolf.view)
		await _wait(1.0)
		Server.command("/cast spell 23001")
		await _wait(10.0)
	sw.clear_target()
	Server.command("/cast spell 3203")
	await _wait(2.0)
	v.ui.windows["conc"].visible = true if v.ui.windows.has("conc") else false
	await _wait(1.0)
	print("[conc] pool ", Server.max_conc, " left ", Server.conc_left, "  list ", Server.conc_list)
	v.ui.chat.run_line("/quit")
	await _wait(5.0)
	print("[quit] scene now: ", get_tree().current_scene.scene_file_path, "  playing ", Server.playing)
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
