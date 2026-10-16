extends Node
## Debug: pets. A level 20 Druid calls a nature spirit (Call Lesser Nature Spirit), it follows, attacks a monster on
## ATTACK, the monster turns on whoever has the most threat, the pet's damage and kill give the owner the experience;
## a second summon is refused; RELEASE. Then an Animist turret at the ground target.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=pet_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	PlayerData.level = 20
	PlayerData.promote(ClassDb.by_name("Druid"))
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	cast._begin(ClassDb.spell(5252))
	await get_tree().create_timer(7.0).timeout
	var p := pets.pet
	print("[pet] pet ", p.spawn.name if p else "none", " L", p.level if p else 0, " hp ", p.max_hp if p else 0, " stats ", p.stats if p else [], " window ", PlayerData.pet)
	cast._begin(ClassDb.spell(5252))
	# it follows
	viewer.player.global_position += Vector3(8, 0, 0)
	await get_tree().create_timer(3.0).timeout
	print("[pet] follow: distance to owner ", snappedf(p.pos.distance_to(viewer.player.global_position), 0.1))
	# attack a monster of about its level
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 8 and st.level <= 12 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	print("[pet] target ", mob.spawn.name, " L", mob.level, " hp ", mob.hp)
	viewer.player.global_position = mob.pos + Vector3(12, 0.3, 0)
	p.pos = viewer.player.global_position + Vector3(1.5, 0, 0)    # it came along
	await get_tree().create_timer(1.5).timeout
	if mob.view:
		viewer.npcs.select(mob.view)
	var xp0 := PlayerData.xp
	PlayerData.pet_command("attack")
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		PlayerData.set_hp(PlayerData.max_hp)
		if i % 5 == 0:
			print("[pet] t=", i, " mob hp ", mob.hp, "/", mob.max_hp, " fighting pet ", mob.target_pet == p, " aggro ", mob.aggro.values(), " pet hp ", p.hp if p else 0)
		if not mob.alive:
			break
	print("[pet] mob alive ", mob.alive, " xp gained ", PlayerData.xp - xp0)
	PlayerData.pet_command("release")
	print("[pet] released: ", pets.pet == null, " window ", PlayerData.pet)
	get_tree().quit()
