extends Node
## Debug: parry / evade / block. A level 20 Hero with Parry and Shields trained, a sword and a shield, takes 2000
## monster swings (tallied against the formulas), then swings 2000 times at a monster with a template evade chance;
## a style animation and the defence clips are played for the screenshot.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=defense_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var out := String(viewer.args.get("out", "user://defense"))
	var combat: Combat = viewer.combat
	PlayerData.level = 20
	PlayerData.promote(ClassDb.by_name("Hero"))
	PlayerData.specs["Parry"] = 20
	PlayerData.specs["Shields"] = 20
	PlayerData.skills_changed.emit()
	PlayerData.inventory[11] = {"id": "small_training_shield", "count": 1}
	PlayerData.active_weapon = "standard"
	print("[def] abilities ", ClassDb.abilities_known(PlayerData.class_id(), PlayerData.level, PlayerData.specs).map(func(a): return "%s %d" % [a.key, a.level]))
	print("[def] stats ", PlayerData.stats, " parry spec ", combat._spec_level("Parry"), " shields ", combat._spec_level("Shields"))
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	var at: Vector3 = mob.pos + Vector3(1.5, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.2
	viewer.player.global_position = at
	viewer.player.face(atan2(-(mob.pos.x - at.x), -(mob.pos.z - at.z)))
	await get_tree().create_timer(0.5).timeout
	var tally := {}
	var count := func(t, _k):
		for k in ["parry", "evade", "block", "misses", "hits you"]:
			if String(t).contains(k):
				tally[k] = int(tally.get(k, 0)) + 1
	PlayerData.message.connect(count)
	mob.fighting = true
	for i in 2000:
		PlayerData.hp = 100000
		combat._npc_blow(mob)
	var stats: Array = combat.casting.effective_stats()
	var pen := CombatRules.defense_penetration(CombatRules.npc_weapon_skill(mob.level, int(mob.stats[0])), mob.level, PlayerData.level)
	print("[def] monster L", mob.level, " vs player: ", tally, "  expected parry ",
		CombatRules.parry_permille(int(stats[2]), 20) * 0.1 * (1 - pen), "%  block (of the rest) ",
		CombatRules.block_permille(int(stats[2]), 20) * 0.1 * (1 - pen), "% x quality/condition, pen ", pen)
	PlayerData.message.disconnect(count)
	mob.fighting = false
	PlayerData.hp = PlayerData.max_hp
	# the player against a monster with a template evade chance
	var ev: NpcState = null
	for s in viewer.npcs.states:
		if int((s as NpcState).spawn.get("defense", [0])[0]) > 0:
			ev = s
			break
	if ev:
		var t2 := {}
		var count2 := func(t, _k):
			for k in ["evades", "parries", "blocks", "miss", "hit for"]:
				if String(t).contains(k):
					t2[k] = int(t2.get(k, 0)) + 1
		PlayerData.message.connect(count2)
		viewer.player.global_position = ev.pos + Vector3(0, 0.2, 1.5)
		ev.yaw = 0.0                                          # facing +Z, toward the player
		for i in 2000:
			ev.hp = 100000
			ev.alive = true
			combat._player_blow(ev, {})
		PlayerData.message.disconnect(count2)
		print("[def] player vs ", ev.spawn.name, " defense ", ev.spawn.defense, ": ", t2)
	# clips
	viewer.player.global_position = at
	combat.set_attack_mode(true)
	print("[def] style clip for 42: ", viewer.player.play_style(42))
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/def_style.png" % out)
	await get_tree().create_timer(1.5).timeout
	viewer.player.defend("block")
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/def_block.png" % out)
	get_tree().quit()
