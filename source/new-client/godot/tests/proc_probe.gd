extends Node
## Debug: style procs. A swing with Maul (stun proc) through Combat._player_blow, then each proc type straight onto a
## monster (bleed ticks, snare, attack-speed slow, stun immunity on a second / third stun, a damage shield on self).
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=proc_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	PlayerData.level = 20
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and int(st.spawn.get("defense", [0])[0]) == 0 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	viewer.player.global_position = mob.pos + Vector3(1.2, 0.2, 0)
	viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
	var maul := ClassDb.style(72)                                # StyleID 72: Maul (crush, stun proc)
	print("[proc] style ", maul.get("name"), " procs ", maul.get("procs"))
	var tries := 0
	while not mob.stunned and tries < 40:
		tries += 1
		combat._player_blow(mob, maul)
	print("[proc] after ", tries, " swings: stunned ", mob.stunned)
	for sid in [20204, 20306, 20088]:
		cast.apply_proc(ClassDb.spell(sid), mob)
	await get_tree().create_timer(0.2).timeout
	print("[proc] snare speed_factor ", mob.speed_factor, " swing_mult ", mob.swing_mult)
	var hp0 := mob.hp
	await get_tree().create_timer(9.0).timeout
	print("[proc] bleed took ", hp0 - mob.hp, " in 9 s")
	# stun immunity: three more stuns inside the window
	for i in 3:
		cast.apply_proc(ClassDb.spell(20401), mob)
		var left := 0.0
		for e in cast.effects:
			if is_same(e.on, mob) and e.kind == "stun":
				left = maxf(left, float(e.until))
		print("[proc] stun #", i + 2, " longest stun left ", snappedf(left, 0.01))
	cast.apply_proc(ClassDb.spell(20123), mob)
	print("[proc] player effects ", cast.player_effects().map(func(e): return e.name))
	get_tree().quit()
