extends Node
## Debug: faction standings and line-of-sight aggro. A curmudgeon (Curmudgeons, base 100 = aggressive) notices the
## player in range; at hostility 60 (hostile) it doesn't and examines "hostile"; with the player hidden below the
## ground it can't see him; 100 siabra kills move Siabras / their enemies' standings.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=faction_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	PlayerData.level = 10
	PlayerData.recalc_max()
	PlayerData.factions = {}
	var mob: NpcState = null
	var siabra: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if st.alive and int(st.spawn.get("faction", 0)) == 76 and int(st.spawn.aggro_level) > 0 and mob == null:
			mob = st
		if st.alive and int(st.spawn.get("faction", 0)) == 107 and siabra == null:
			siabra = st
	if mob == null or siabra == null:
		print("[faction] no curmudgeon / siabra")
		get_tree().quit()
		return
	print("[faction] ", mob.spawn.name, " L", mob.level, " aggro range ", mob.spawn.aggro_range, " standing ", PlayerData.faction_standing(76))
	for trial in [["base 100", -1, 0.0], ["hostility 60", 60, 0.0], ["below ground", -1, -12.0]]:
		PlayerData.factions = {} if int(trial[1]) < 0 else {"76": int(trial[1])}
		mob.fighting = false
		mob.aggro = {}
		var at := mob.pos + Vector3(3, 0, 0)
		at.y = viewer.zone.height_at(at.x, at.z) + 0.3 + float(trial[2])
		viewer.player.global_position = at
		viewer.player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("[faction] ", trial[0], ": sees ", combat._sees_player(mob), ", aggressive ", combat._faction_aggressive(mob),
				", stance ", (mob.view as Npc).stance() if mob.view else "?", ", fighting ", mob.fighting)
		mob.fighting = false
		mob.aggro = {}
	# the sight ray itself: to a point 12 m under the ground 20 m away, and to one 1 m above it
	var space: PhysicsDirectSpaceState3D = viewer.player.get_world_3d().direct_space_state
	for dy in [-12.0, 1.0]:
		var p: Vector3 = mob.pos + Vector3(20, 0, 0)
		p.y = viewer.zone.height_at(p.x, p.z) + dy
		var q := PhysicsRayQueryParameters3D.create(mob.pos + Vector3(0, 1.5, 0), p, ZoneLoader.LAYER_WALL | ZoneLoader.LAYER_FLOOR)
		print("[faction] ray to ground ", dy, " m: blocked ", not space.intersect_ray(q).is_empty(), " player y now ",
				snappedf(viewer.player.global_position.y - viewer.zone.height_at(viewer.player.global_position.x, viewer.player.global_position.z), 0.1))
	for k in 8:
		var a := k * TAU / 8.0
		var p2: Vector3 = mob.pos + Vector3(sin(a), 0, cos(a)) * 10.0
		p2.y = viewer.zone.height_at(p2.x, p2.z) + 1.5
		var q2 := PhysicsRayQueryParameters3D.create(mob.pos + Vector3(0, 1.5, 0), p2, ZoneLoader.LAYER_WALL | ZoneLoader.LAYER_FLOOR)
		var hit := space.intersect_ray(q2)
		print("[faction] dir ", k, " mob y-ground ", snappedf(mob.pos.y - viewer.zone.height_at(mob.pos.x, mob.pos.z), 0.01), " hit ",
				(str((hit.collider as Node).name) + " at " + str(snappedf(mob.pos.distance_to(hit.position), 0.1)) + " layer " + str((hit.collider as CollisionObject3D).collision_layer)) if not hit.is_empty() else "-")
	PlayerData.factions = {}
	var said := [0]
	PlayerData.message.connect(func(t, _k): if String(t).begins_with("Your relationship"): said[0] += 1)
	for i in 100:
		PlayerData.faction_killed(107)
	print("[faction] 100 siabra kills: ", said, " messages; hostility ", PlayerData.factions)
	get_tree().quit()
