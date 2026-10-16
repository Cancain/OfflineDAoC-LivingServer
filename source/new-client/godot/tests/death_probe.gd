extends Node
## Debug: death at level 8 (experience loss), /release (second loss into a gravestone, constitution loss), /pray at the
## grave (experience back), then a healer restoring the constitution. The chat is printed.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=death_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var out := String(viewer.args.get("out", "user://death"))
	var combat: Combat = viewer.combat
	PlayerData.level = 8
	PlayerData.xp = (CombatRules.xp_for_level(8) + CombatRules.xp_for_level(9)) / 2
	PlayerData.set_copper(5000)
	var xp0 := PlayerData.xp
	print("[death] level 8 xp ", xp0, " con ", PlayerData.con_now(), " max hp ", PlayerData.max_hp)
	var spot: Vector3 = viewer.player.global_position + Vector3(-12, 0, 14)
	spot.y = viewer.zone.height_at(spot.x, spot.z) + 0.2
	viewer.player.global_position = spot
	await get_tree().create_timer(0.5).timeout
	combat._player_died()
	print("[death] after death xp ", PlayerData.xp, " lost ", xp0 - PlayerData.xp)
	await get_tree().create_timer(1.0).timeout
	var xp1 := PlayerData.xp
	PlayerData.release_requested.emit()                      # too early: auto release in 9 s
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/death_window.png" % out)
	await get_tree().create_timer(8.0).timeout
	print("[death] after release xp ", PlayerData.xp, " lost ", xp1 - PlayerData.xp, " con lost ", PlayerData.con_lost,
		" max hp ", PlayerData.max_hp, " grave ", PlayerData.grave, " at ", viewer.player.global_position)
	print("[death] effect icons: ", viewer.ui._effects_bar.get_child_count(), " (con icon ", viewer.ui._con_icon_shown, ")  CON ",
			PlayerData.effective_stats()[1], " normally ", PlayerData.unmodified_stat(1))
	for m in combat._grave.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		print("[death] grave mesh ", mi.name, " aabb ", mi.global_transform * mi.get_aabb())
	# look at the grave
	var g: Array = PlayerData.grave.pos
	var gp := Vector3(g[0], g[1], g[2])
	var gy := float(PlayerData.grave.get("yaw", 0.0))
	viewer.player.global_position = gp + Vector3(-sin(gy), 0, -cos(gy)) * 4.0
	viewer.player.face(atan2(-(gp.x - viewer.player.global_position.x), -(gp.z - viewer.player.global_position.z)))
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/death_grave.png" % out)
	PlayerData.pray_requested.emit()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/death_pray.png" % out)
	await get_tree().create_timer(4.5).timeout
	print("[death] after pray xp ", PlayerData.xp, " grave ", PlayerData.grave, " sitting ", viewer.player.sitting)
	PlayerData.sit_requested.emit(false)
	PlayerData.sit_requested.emit(false)
	PlayerData.sit_requested.emit(true)
	PlayerData.end_pts = 50
	await get_tree().create_timer(3.2).timeout
	print("[death] sitting 3 s: endurance 50 -> ", PlayerData.end_pts)
	# a healer
	var healer: Npc = null
	for st in viewer.npcs.states:
		var s: NpcState = st
		if str(s.spawn.get("role", "")) == "healer" and s.view:
			if healer == null or s.pos.distance_to(viewer.player.global_position) < healer.global_position.distance_to(viewer.player.global_position):
				healer = s.view
	if healer == null:
		var near: NpcState = null
		for st in viewer.npcs.states:
			if str((st as NpcState).spawn.get("role", "")) == "healer":
				near = st
		viewer.player.global_position = near.pos + Vector3(2, 0.2, 0)
		await get_tree().create_timer(2.0).timeout
		healer = near.view
	viewer.player.global_position = healer.global_position + Vector3(2, 0.2, 0)
	await get_tree().create_timer(1.0).timeout
	viewer._on_interact(healer)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/death_healer.png" % out)
	for b in viewer.ui.root.find_children("*", "Button", true, false):
		if (b as Button).text == "ACCEPT":
			print("[death] healer box: ", (b.get_parent().find_children("*", "Label", false, false) as Array).map(func(l): return l.text))
			(b as Button).pressed.emit()
			break
	print("[death] after healer con lost ", PlayerData.con_lost, " max hp ", PlayerData.max_hp, " copper ", PlayerData.total_copper())
	get_tree().quit()
