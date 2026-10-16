extends Node
## Debug: stealth. A level 20 Nightshade (Stealth 20) hides away from monsters, walks right next to an aggressive one
## unnoticed (speed share printed), then backstabs it from behind (a Critical Strike opener needs stealth) and is out.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=stealth_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var abil: Abilities = combat.abilities
	PlayerData.level = 20
	PlayerData.promote(ClassDb.by_name("Nightshade"))
	PlayerData.specs["Stealth"] = 20
	PlayerData.specs["Critical Strike"] = 20
	PlayerData.recalc_max()
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and int(st.spawn.aggro_level) > 0 and int(st.spawn.aggro_range) > 0 and st.level >= 12 \
				and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	print("[stealth] target ", mob.spawn.name, " L", mob.level, " aggro range ", mob.spawn.aggro_range)
	viewer.player.global_position = mob.pos + Vector3(60, 0.3, 0)
	await get_tree().create_timer(1.0).timeout
	abil.toggle_stealth()
	print("[stealth] hidden ", abil.stealthed, " speed share ", snappedf(viewer.player.stealth_mult, 0.001))
	# right behind it
	var back := Vector3(-sin(mob.yaw), 0, -cos(mob.yaw)) * 1.5
	viewer.player.global_position = mob.pos + back + Vector3(0, 0.3, 0)
	viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
	await get_tree().create_timer(3.0).timeout
	print("[stealth] next to it for 3 s: it fights ", mob.fighting)
	if mob.view:
		viewer.npcs.select(mob.view)
	var bs := {}
	for st in ClassDb.styles_known(PlayerData.class_id(), PlayerData.specs):
		if String(st.get("name", "")) == "Backstab":
			bs = st
	back = Vector3(-sin(mob.yaw), 0, -cos(mob.yaw)) * 1.5          # it may have turned while roaming
	viewer.player.global_position = mob.pos + back + Vector3(0, 0.3, 0)
	viewer.player.face(atan2(-(mob.pos.x - viewer.player.global_position.x), -(mob.pos.z - viewer.player.global_position.z)))
	print("[stealth] facing it: ", combat._in_front_of_player(mob.pos, 120.0), " backstab ok from stealth: ", combat._style_ok(bs, mob))
	combat._player_blow(mob, bs)
	print("[stealth] after the blow: hidden ", abil.stealthed, " backstab ok now: ", combat._style_ok(bs, mob))
	get_tree().quit()
