extends Node
## Debug: guards attack monsters near them (GuardBrain). A monster is put 12 m from a Sentinel; the guard should engage,
## kill it and walk back to its post; no experience for the player standing by.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=guard_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var g: NpcState = null
	var m: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if g == null and st.spawn.get("role") == "guard" and String(st.spawn.name) == "Sentinel":
			g = st
		if m == null and st.alive and int(st.spawn.realm) == 0 and st.level >= 6 and st.level <= 12 and int(st.spawn.aggro_level) == 0:
			m = st
	if g == null or m == null:
		print("[guard] none found")
		get_tree().quit()
		return
	var post := g.pos
	m.pos = g.pos + Vector3(12, 0, 0)
	m.pos.y = viewer.npcs.ground_at(m.pos)
	m.home = m.pos
	var at := g.pos + Vector3(-10, 0, 8)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.3
	viewer.player.global_position = at
	var xp0 := PlayerData.xp
	print("[guard] ", g.spawn.name, " L", g.level, " vs ", m.spawn.name, " L", m.level)
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		viewer.player.global_position = at
		if i % 3 == 0 or not m.alive:
			print("[guard] t", i, " guard fighting ", g.fighting, " hp ", g.hp, "/", g.max_hp, " | ", m.spawn.name, " ", m.hp, "/", m.max_hp, " fighting ", m.fighting)
		if not m.alive:
			break
	await get_tree().create_timer(15.0).timeout
	print("[guard] after: guard fighting ", g.fighting, " from post ", snappedf(g.pos.distance_to(post), 0.1), " m; xp change ", PlayerData.xp - xp0)
	get_tree().quit()
