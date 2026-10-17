extends Node
## Debug: Critical Shot and Rapid Fire. A level 30 Ranger (Recurve Bow 30) with a bow fires a normal shot, a critical
## shot (twice the draw, x2 damage on a lower monster, no normal crit) and rapid-fire shots (half the draw, ~half damage).
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=shots_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	PlayerData.level = 30
	PlayerData.promote(ClassDb.by_name("Ranger"))
	PlayerData.specs["Recurve Bow"] = 30
	PlayerData.recalc_max()
	PlayerData.inventory[13] = {"id": "elm_short_recurve_bow3", "count": 1}
	PlayerData.inventory[PlayerData.first_free()] = {"id": "bodkin_arrows3", "count": 40}
	PlayerData.set_active_weapon("ranged")
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 8 and st.level <= 14 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	var at := mob.pos + Vector3(12, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.2
	viewer.player.global_position = at
	await get_tree().create_timer(3.0).timeout
	print("[shots] view ", mob.view != null)
	if mob.view:
		viewer.npcs.select(mob.view)
	for kind in ["normal", "critical", "rapid", "rapid"]:
		PlayerData.end_pts = PlayerData.MAX_END
		mob.stunned = true                                        # it doesn't fight back here
		viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
		if kind == "critical":
			combat.critical_shot()
		else:
			if kind == "rapid" and not combat.rapid_fire_on:
				combat.rapid_fire()
			combat.ranged_attack()
		await get_tree().create_timer(combat._draw_total + 0.2).timeout
		viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
		mob.stunned = true
		combat.ranged_attack()
		await get_tree().create_timer(1.5).timeout
	get_tree().quit()
