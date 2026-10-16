extends Node
## Debug: Engage / Stag / Berserk. A level 20 Hero with Shields 20 and a shield takes 30 blows from a monster without and
## with Engage (blocks counted), then uses Stag (max health up, then back); a Berserker's swings all crit.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=abilities_probe
var viewer: Node
var blocks := 0


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	var abil: Abilities = combat.abilities
	PlayerData.message.connect(func(t, _k):
		if String(t).contains("block the blow") and not String(t).begins_with("You concentrate"):
			blocks += 1)
	PlayerData.level = 20
	PlayerData.promote(ClassDb.by_name("Hero"))
	PlayerData.specs["Shields"] = 20
	PlayerData.inventory[11] = {"id": "small_training_shield", "count": 1}
	PlayerData.active_weapon = "standard"
	PlayerData.recalc_max()
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 10 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	viewer.player.global_position = mob.pos + Vector3(1.5, 0.3, 0)
	viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
	await get_tree().create_timer(6.0).timeout                         # nothing hit it for 5 s
	if mob.view:
		viewer.npcs.select(mob.view)
	mob.fighting = true
	for i in 30:
		PlayerData.set_hp(PlayerData.max_hp)
		combat._npc_blow(mob)
	print("[abil] blocks without engage: ", blocks, "/30")
	blocks = 0
	abil.toggle_engage()
	for i in 30:
		PlayerData.set_hp(PlayerData.max_hp)
		PlayerData.end_pts = PlayerData.MAX_END
		viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
		combat._npc_blow(mob)
	print("[abil] blocks with engage: ", blocks, "/30, still engaged ", abil.engaged != null)
	abil.end_engage(true)
	var hp0 := PlayerData.max_hp
	abil.stag()
	print("[abil] stag: max hp ", hp0, " -> ", PlayerData.max_hp)
	PlayerData.promote(ClassDb.by_name("Berserker"))
	PlayerData.recalc_max()
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	abil.berserk()
	print("[abil] berserk left ", abil.berserk_left)
	var crits := 0
	PlayerData.message.connect(func(t, _k):
		if String(t).contains("critical hit"):
			crits += 1)
	mob.max_hp = 100000
	mob.hp = 100000
	for i in 10:
		combat._player_blow(mob, {})
	print("[abil] berserk crits ", crits, " of 10 swings (misses / defences count against)")
	get_tree().quit()
