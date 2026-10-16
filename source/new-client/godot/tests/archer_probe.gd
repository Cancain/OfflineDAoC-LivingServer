extends Node
## Debug: monster archers. A sheevra archer (Silvermine) shoots the player standing 20 m off; after the player hits it,
## it closes to melee.
##   --headless --skip-login --zone=201 --figure=cel_m --ui-test --probe=archer_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	PlayerData.level = 25
	PlayerData.recalc_max()
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if String(st.spawn.name) == "sheevra archer" and st.alive:
			mob = st
			break
	print("[archer] ", mob.spawn.name, " L", mob.level, " gear ", combat._npc_gear(mob).keys())
	var at := mob.pos + Vector3(20, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.3
	viewer.player.global_position = at
	combat._engage(mob)
	for i in 12:
		await get_tree().create_timer(1.0).timeout
		viewer.player.global_position = at
		PlayerData.set_hp(PlayerData.max_hp)
	print("[archer] distance after 12 s ", snappedf(mob.pos.distance_to(viewer.player.global_position), 0.1), " melee_forced ", mob.melee_forced)
	combat.add_aggro(mob, "player", 10)                              # the player's hit
	for i in 6:
		await get_tree().create_timer(1.0).timeout
		viewer.player.global_position = at
		PlayerData.set_hp(PlayerData.max_hp)
	print("[archer] after being hit: distance ", snappedf(mob.pos.distance_to(viewer.player.global_position), 0.1), " melee_forced ", mob.melee_forced)
	get_tree().quit()
