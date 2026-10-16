extends Node
## Debug (bot plan phase 6, owner 2026-10-11): your companions ride a stable route behind you - two companions hired,
## a ticket bought at Rumdor (Mag Mell), the ride; their distance behind you as you go, pictures, where they end up.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=companion_ride_probe --out=<folder>
var v: Node


func shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ready() -> void:
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://ride"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(6.0).timeout
	var comps: Companions = v.companions
	PlayerData.gain_xp(CombatRules.xp_for_level(5) - PlayerData.xp, false)
	PlayerData.promote(44)                                 # a Hero: past the base class's level 5, two slots at 15
	PlayerData.gain_xp(CombatRules.xp_for_level(16) - PlayerData.xp, false)
	PlayerData.set_copper(1000000)
	var rng := RandomNumberGenerator.new()
	var classes := Companions.classes_for("hib", 0)
	var stable: NpcState = null
	for s in v.npcs.states:
		if String((s as NpcState).spawn.name) == "Rumdor":
			stable = s
	var at := stable.pos + Vector3(2, 0, 0)
	at.y = v.zone.height_at(at.x, at.z) + 0.3
	v.player.global_position = at
	await get_tree().create_timer(1.0).timeout
	for i in 2:
		comps.hire(0, i, int(classes[i * 3].id), ["Riderone", "Ridertwo"][i], CharacterFactory.random_look("cel_m", rng), "Test")
	await get_tree().create_timer(3.0).timeout
	var ids: Array = Array(WorldLink.bots.call("CompanionIds"))
	print("[ride] companions in the world: ", ids)
	PlayerData.buy("HS_MagMell_ParthenonFarm", "Rumdor")
	var cam := Camera3D.new()
	v.add_child(cam)
	var max_gap := 0.0
	for t in 70:
		await get_tree().create_timer(1.0).timeout
		var pp: Vector3 = v.player.global_position
		var gaps := []
		for id in ids:
			var cp: Vector3 = WorldLink.bots.call("CompanionPos", id)
			gaps.append(snappedf(cp.distance_to(pp), 0.1))
			if v.player.riding:
				max_gap = maxf(max_gap, cp.distance_to(pp))
		if t % 4 == 0 or HorseRoutes.ride.is_empty():
			print("[ride] t%d riding %s point %s gaps %s" % [t, v.player.riding, HorseRoutes.ride.get("i", "-"), gaps])
		if t == 12 or t == 24:
			var fwd := Vector3(-sin(v.player.facing()), 0, -cos(v.player.facing()))
			cam.global_position = pp - fwd * 4.0 + Vector3(0, 6, 0) + Vector3(fwd.z, 0, -fwd.x) * 8.0
			cam.look_at(pp - fwd * 6.0)
			cam.current = true
			await shot(out, "ride_t%d" % t)
			cam.current = false
		if t == 16 and ids.size() > 0:                    # close beside you and beside the first companion: the seats
			for who in ["you", "companion"]:
				var spot: Vector3 = pp if who == "you" else WorldLink.bots.call("CompanionPos", ids[0])
				var f2 := Vector3(-sin(v.player.facing()), 0, -cos(v.player.facing()))
				var side := Vector3(f2.z, 0, -f2.x)
				cam.global_position = spot + side * 3.2 + Vector3(0, 0.6, 0)
				cam.look_at(spot)
				cam.current = true
				await shot(out, "seat_" + who)
			cam.current = false
		if HorseRoutes.ride.is_empty() and t > 6:
			await get_tree().create_timer(4.0).timeout
			break
	var pp2: Vector3 = v.player.global_position
	for id in ids:
		var cp: Vector3 = WorldLink.bots.call("CompanionPos", id)
		print("[ride] after the ride: companion %d is %.1f m from you" % [id, cp.distance_to(pp2)])
	print("[ride] largest gap while riding: %.1f m" % max_gap)
	cam.global_position = pp2 + Vector3(6, 4, 6)
	cam.look_at(pp2)
	cam.current = true
	await shot(out, "ride_end")
	get_tree().quit()
