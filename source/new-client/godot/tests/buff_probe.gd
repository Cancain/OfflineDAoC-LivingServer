extends Node
## Debug: buffs. A level 20 Hero gets stat, armour, damage add / shield, haste, speed and regeneration buffs; the
## effective stats, max HP, armour, swing time and a few blows each way are printed.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=buff_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	PlayerData.level = 20
	PlayerData.promote(ClassDb.by_name("Hero"))
	PlayerData.recalc_max()
	var w := combat._weapon()
	print("[buff] before: stats ", PlayerData.effective_stats(), " max hp ", PlayerData.max_hp, " swing ", snappedf(combat._player_swing_seconds(w), 0.01))
	PlayerData.inventory[25] = {"id": "rawhide_brea_jerkin", "count": 1}
	print("[buff] torso armour (AF, absorb) before ", _torso(combat))
	for sid in [1451, 3262, 1, 1031, 12, 52, 402, 412, 1112]:
		cast._apply_friendly(ClassDb.spell(sid))
	print("[buff] sums ", PlayerData.buffs)
	print("[buff] after: stats ", PlayerData.effective_stats(), " max hp ", PlayerData.max_hp, " swing ", snappedf(combat._player_swing_seconds(w), 0.01), " speed x", viewer.player.buff_speed)
	print("[buff] torso armour (AF, absorb) after ", _torso(combat))
	print("[buff] effects bar ", cast.player_effects().map(func(e): return e.name))
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and int(st.spawn.get("defense", [0])[0]) == 0 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	viewer.player.global_position = mob.pos + Vector3(1.2, 0.2, 0)
	PlayerData.message.connect(_show)
	mob.fighting = true
	for i in 6:
		combat._player_blow(mob, {})
		PlayerData.hp = PlayerData.max_hp
		combat._npc_blow(mob)
	get_tree().quit()


func _torso(combat: Combat) -> Array:
	seed(1)                                                     # the hit location roll: same piece both times
	var best := [0.0, 0.0]
	for i in 40:
		var a: Array = combat._worn_armor()
		if a[0] > best[0]:
			best = a
	return [snappedf(best[0], 0.01), snappedf(best[1], 0.001)]


func _show(t: String, _k: String) -> void:
	if t.contains("extra damage") or (t.begins_with("You hit") and not t.contains("attack")):
		print("[chat] ", t)
