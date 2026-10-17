extends Node
## Debug: resists, debuffs and area spells. A Lough Derg animal's racial resists (Race 2000: cold / thrust -15, slash
## +5), its absorb and stats before / after Mesh of Force (DEX / QUI) and Banish Will (STR / CON) debuffs, a heat
## resist debuff, disease; the player's own resists; an area spell's targets and falloff around a ground target.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=resist_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	PlayerData.level = 40
	PlayerData.recalc_max()
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and int(st.spawn.get("race", 0)) == 2000 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	print("[resist] mob ", mob.spawn.name, " L", mob.level, " race ", mob.spawn.race, " dmg type ", mob.spawn.damage_type)
	for dt in [1, 2, 3, 11, 13]:
		print("[resist]   resist ", CombatRules.DAMAGE_NAMES[dt], " ", mob.resist(dt))
	print("[resist] before: STR/CON/DEX/QUI ", [mob.eff(0), mob.eff(1), mob.eff(2), mob.eff(3)], " absorb ", snappedf(mob.absorb(), 0.0001), " heat ", mob.resist(13))
	mob.max_hp = 100000
	mob.hp = 100000
	for sid in [622, 962, 776, 731]:
		var sp := ClassDb.spell(sid)
		for k in 10:                                             # until it lands (resists roll)
			var n := cast.effects.size()
			cast._apply_hostile(sp, mob)
			if cast.effects.size() > n:
				break
	print("[resist] after:  STR/CON/DEX/QUI ", [mob.eff(0), mob.eff(1), mob.eff(2), mob.eff(3)], " absorb ", snappedf(mob.absorb(), 0.0001), " heat ", mob.resist(13),
			" diseased ", mob.diseased, " speed ", mob.speed_factor)
	print("[resist] player (", PlayerData.character.get("base", ""), ") resists body/cold/crush/heat/spirit/slash ",
			[PlayerData.resist(10), PlayerData.resist(11), PlayerData.resist(1), PlayerData.resist(13), PlayerData.resist(15), PlayerData.resist(2)])
	# an area spell around a ground target on the mob
	var area := ClassDb.spell(81)
	cast.ground_target = mob.pos
	cast._cast_mode = "area"
	var hits := cast._area_targets(area)
	print("[resist] area ", area.name, " radius ", area.radius, " hits ", hits.size(), ": ", hits.map(func(h): return "%s %.2f" % [h[0].spawn.name, h[1]]))
	get_tree().quit()
