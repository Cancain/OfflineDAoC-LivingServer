extends Node
## Debug: monster spells. A level 10 player 15 m from a dergan enchanter (Amethyst Shield, Moon Ray, Prismatic Flare):
## it buffs its armour, casts at range, its stun lands once and then the player is immune; a blow during a cast
## interrupts it. The player's health is topped up so the whole spell set shows.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=npc_spell_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	PlayerData.level = 10
	PlayerData.recalc_max()
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if String(st.spawn.name) == "dergan enchanter" and st.alive and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	print("[npcspell] mob ", mob.spawn.name, " L", mob.level, " spells ", mob.spawn.spells, " martial ", mob.spawn.get("martial"), " stats ", mob.stats)
	mob.max_hp = 100000
	mob.hp = 100000
	var at := mob.pos + Vector3(15, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.2
	viewer.player.global_position = at
	combat._engage(mob)
	var interrupted := false
	for i in 80:                                                  # 40 s
		await get_tree().create_timer(0.5).timeout
		PlayerData.set_hp(PlayerData.max_hp)
		if combat.npc_casting.busy(mob) and not interrupted and i > 20:
			interrupted = true
			combat._player_blow(mob, {})
		if i % 10 == 0:
			print("[npcspell] t=", i * 0.5, " af_bonus ", mob.af_bonus, " player cc '", viewer.player.cc, "' snare ", viewer.player.snare_mult,
					" dist ", snappedf(mob.pos.distance_to(viewer.player.global_position), 0.1), " effects ", combat.casting.player_effects().map(func(e): return e.name))
	get_tree().quit()
