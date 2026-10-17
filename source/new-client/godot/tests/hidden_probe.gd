extends Node
## Debug: stealthed monsters (the STEALTH flag - ambushers): hidden and untargetable until they fight, hidden again
## when they go home alive.
##   --headless --skip-login --zone=206 --figure=cel_m --ui-test --probe=hidden_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	PlayerData.level = 40
	PlayerData.recalc_max()
	var m: NpcState = null
	for s in viewer.npcs.states:
		if (s as NpcState).stealthed:
			m = s
			break
	if m == null:
		print("[hidden] none")
		get_tree().quit()
		return
	var at := m.pos + Vector3(6, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.3
	viewer.player.global_position = at
	await get_tree().create_timer(2.0).timeout
	var v: Npc = m.view
	print("[hidden] ", m.spawn.name, " L", m.level, " stealthed ", m.stealthed, " view ", v != null, " visible ", v.visible if v else "-",
			" nearest_enemy is it ", viewer.npcs.nearest_enemy(30.0) == v)
	combat.add_aggro(m, "player", 1)
	await get_tree().create_timer(0.5).timeout
	print("[hidden] fighting ", m.fighting, " stealthed ", m.stealthed, " visible ", m.view.visible if m.view else "-")
	m.go_home()
	print("[hidden] after go_home stealthed ", m.stealthed)
	get_tree().quit()
