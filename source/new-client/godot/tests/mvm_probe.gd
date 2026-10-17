extends Node
## Debug: monster-vs-monster faction fights. A siabra (Siabras: enemies Curmudgeons ...) is put next to a curmudgeon,
## the player 60 m off; they should find each other, fight to a death, and the survivor go home. No experience.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=mvm_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	var chat := [0]
	PlayerData.message.connect(func(t, _k): chat[0] += 1; print("[chat] ", t))
	var a: NpcState = null
	var b: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if not st.alive or int(st.spawn.aggro_level) <= 0:
			continue
		if a == null and int(st.spawn.get("faction", 0)) == 107:
			a = st
		if b == null and int(st.spawn.get("faction", 0)) == 76:
			b = st
	if a == null or b == null:
		print("[mvm] none found")
		get_tree().quit()
		return
	b.pos = a.pos + Vector3(4, 0, 0)
	b.pos.y = viewer.npcs.ground_at(b.pos)
	b.home = b.pos
	var at := a.pos + Vector3(-60, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.3
	viewer.player.global_position = at
	var xp0 := PlayerData.xp
	print("[mvm] ", a.spawn.name, " L", a.level, " vs ", b.spawn.name, " L", b.level)
	for i in 40:
		await get_tree().create_timer(1.0).timeout
		viewer.player.global_position = at
		if i % 4 == 0 or not (a.alive and b.alive):
			print("[mvm] t", i, " ", a.spawn.name, " ", a.hp, "/", a.max_hp, " fighting ", a.fighting, " | ", b.spawn.name, " ", b.hp, "/", b.max_hp, " fighting ", b.fighting)
		if not (a.alive and b.alive):
			break
	await get_tree().create_timer(3.0).timeout
	var w: NpcState = a if a.alive else b
	print("[mvm] survivor ", w.spawn.name, " fighting ", w.fighting, " aggro ", w.aggro.size(), "; player xp change ", PlayerData.xp - xp0, "; player chat lines ", chat[0])
	get_tree().quit()
