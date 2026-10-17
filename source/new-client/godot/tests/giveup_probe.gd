extends Node
## Debug: a monster that can't reach you leaves the fight after 25 s without combat (StandardMobState_AGGRO) and walks
## home; threat fades with distance.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=giveup_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	PlayerData.level = 20
	PlayerData.recalc_max()
	var m: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if st.alive and int(st.spawn.realm) == 0 and st.level >= 5 and int(st.spawn.aggro_level) == 0 and not st.spawn.has("path"):
			m = st
			break
	m.run_speed = 0.3                                     # it can't keep up
	var at := m.pos + Vector3(30, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.3
	viewer.player.global_position = at
	combat.add_aggro(m, "player", 50)
	print("[giveup] ", m.spawn.name, " fighting ", m.fighting)
	for t in 32:
		await get_tree().create_timer(1.0).timeout
		viewer.player.global_position = at
		if t in [10, 20, 24, 26, 28, 31]:
			print("[giveup] t", t + 1, " fighting ", m.fighting, " returning ", m.returning, " from home ", snappedf(m.pos.distance_to(m.home), 0.1))
	print("[giveup] threat 100 at 6 m / 37.5 m / 150 m counts ", [100, ceilf(100 * exp(Combat.THREAT_FADE * (1500 - 250))), ceilf(100 * exp(Combat.THREAT_FADE * (6000 - 250)))])
	get_tree().quit()
