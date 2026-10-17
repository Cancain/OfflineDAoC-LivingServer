extends Node
## Debug: friendly spell types. A pulsing chant (Brisk Wind: cast once, pulses every 6 s, cast again to cancel),
## bladeturn and ablative armour against a monster's blows, a heal over time, a cure poison on a monster's DoT.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=friendly_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	PlayerData.level = 30
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 8 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	# 1. a pulsing chant
	cast._begin(ClassDb.spell(411))
	await get_tree().create_timer(3.5).timeout
	print("[friendly] pulse ", cast.pulse.get("spell", {}).get("name", "-"), " speed buff ", PlayerData.buffs.get("speed"), " effects ", cast.player_effects().map(func(e): return "%s %.1f" % [e.name, e.seconds]))
	await get_tree().create_timer(9.0).timeout
	print("[friendly] after 9 s: effects ", cast.player_effects().map(func(e): return "%s %.1f" % [e.name, e.seconds]))
	cast._begin(ClassDb.spell(411))
	print("[friendly] recast: pulse ", cast.pulse.is_empty())
	# 2. bladeturn + ablative against blows
	cast._apply_friendly(ClassDb.spell(111))
	cast._apply_friendly(ClassDb.spell(1198))
	mob.fighting = true
	for i in 30:
		PlayerData.set_hp(PlayerData.max_hp)
		combat._npc_blow(mob)
	mob.fighting = false
	# 3. heal over time
	PlayerData.set_hp(PlayerData.max_hp / 2)
	cast._apply_friendly(ClassDb.spell(3131))
	await get_tree().create_timer(7.0).timeout
	# 4. a monster's poison, then a cure
	cast.apply_to_player(NpcCasting.spell(6348), mob, 40)
	print("[friendly] poisoned: ", cast.player_effects().map(func(e): return e.name))
	cast._apply_friendly(ClassDb.spell(1371))
	await get_tree().create_timer(0.2).timeout
	print("[friendly] cured: ", cast.player_effects().map(func(e): return e.name))
	get_tree().quit()
