extends Node
## Debug: old archery. A level 10 Ranger with an elm short recurve bow and bodkin arrows draws, fires at a monster
## 20 m off (twice), and once has the draw interrupted by moving.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=ranged_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var out := String(viewer.args.get("out", "user://ranged"))
	var combat: Combat = viewer.combat
	PlayerData.level = 10
	PlayerData.promote(ClassDb.by_name("Ranger"))
	PlayerData.specs["Recurve Bow"] = 10
	PlayerData.recalc_max()
	PlayerData.inventory[13] = {"id": "elm_short_recurve_bow3", "count": 1}
	PlayerData.inventory[PlayerData.first_free()] = {"id": "bodkin_arrows3", "count": 20}
	PlayerData.set_active_weapon("ranged")
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level <= 6 and st.pos.distance_to(viewer.player.global_position) > 60.0 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	var at := mob.pos + Vector3(20, 0, 0)
	var space := (viewer as Node3D).get_world_3d().direct_space_state
	for k in 16:                                               # a spot 20 m off with a clear line to it
		var a := k * TAU / 16.0
		var c := mob.pos + Vector3(cos(a), 0, sin(a)) * 20.0
		c.y = viewer.zone.height_at(c.x, c.z) + 0.2
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.6, 0), mob.pos + Vector3(0, 1.0, 0), ZoneLoader.LAYER_WALL)
		if space.intersect_ray(q).is_empty():
			at = c
			break
	at.y = viewer.zone.height_at(at.x, at.z) + 0.2
	viewer.player.global_position = at
	viewer.player.face(atan2(-(mob.pos.x - at.x), -(mob.pos.z - at.z)))
	await get_tree().create_timer(1.0).timeout
	if mob.view:
		viewer.npcs.select(mob.view)
	for shot in 2:
		combat.ranged_attack()
		await get_tree().create_timer(4.3).timeout
		if shot == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/ranged_aim.png" % out)
		combat.ranged_attack()
		await get_tree().create_timer(1.5).timeout
	print("[ranged] arrows left ", PlayerData.entry(PlayerData.find_item("bodkin_arrows3")).get("count", 0), " endurance ", PlayerData.end_pts, " mob hp ", mob.hp)
	combat.ranged_attack()
	await get_tree().create_timer(0.5).timeout
	viewer.player.velocity = Vector3(3, 0, 0)
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
