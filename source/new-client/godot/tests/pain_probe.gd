extends Node
## Debug: pain / hit sounds for an Elf mage and a lucradan outside Mag Mell (owner 2026-10-10: silent).
##   --headless --skip-login --zone=200 --figure=elf_m --ui-test --probe=pain_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var p: Player = v.player
	print("[pain] player sounds: ", p.sounds != null, " set ", (p.sounds.sheet.get("name", "") if p.sounds else ""), " bus Ambient vol ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambient")), " muted ", AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambient")))
	var luc: NpcState = null
	for s in v.npcs.states:
		if "lucradan" in String((s as NpcState).spawn.name):
			luc = s
			break
	p.global_position = luc.pos + Vector3(2.5, 0.3, 0)
	await get_tree().create_timer(1.5).timeout
	var n: Npc = luc.view
	print("[pain] lucradan view ", n != null, " sounds ", n != null and n.sounds != null, " set ", (n.sounds.sheet.get("name", "") if n and n.sounds else ""))
	if p.sounds:
		p.sounds.event("pain_light")
	if n and n.sounds:
		n.sounds.event("pain_light")
	await get_tree().create_timer(0.8).timeout
	print("[pain] player played: ", p.sounds.play_log if p.sounds else "-")
	print("[pain] lucradan played: ", n.sounds.play_log if n and n.sounds else "-")
	get_tree().quit()
