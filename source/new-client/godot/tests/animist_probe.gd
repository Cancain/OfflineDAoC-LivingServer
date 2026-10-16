extends Node
## Debug: Animist pets. A level 30 Animist sets a ground target by a monster pack, plants a Battle Messenger turret
## there, casts Briar Cloud (an area spell around the turret), sends a Reviving Spirit bomber to it, then Release Clump.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=animist_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	PlayerData.level = 30
	PlayerData.promote(ClassDb.by_name("Animist"))
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 12 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	viewer.player.global_position = mob.pos + Vector3(14, 0.3, 0)
	await get_tree().create_timer(1.0).timeout
	cast.ground_target = mob.pos + Vector3(3, 0, 0)
	cast._begin(ClassDb.spell(11671))
	await get_tree().create_timer(4.0).timeout
	print("[animist] turret ", pets.pet.spawn.name if pets.pet else "none", " at ", pets.pet.pos if pets.pet else Vector3.ZERO)
	cast._begin(ClassDb.spell(11635))
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		PlayerData.set_hp(PlayerData.max_hp)
	print("[animist] mob hp after Briar Cloud ", mob.hp)
	pets.pet.hp = pets.pet.max_hp / 2
	cast._begin(ClassDb.spell(11503))
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		PlayerData.set_hp(PlayerData.max_hp)
	print("[animist] turret hp after the bomber ", pets.pet.hp if pets.pet else -1, "/", pets.pet.max_hp if pets.pet else -1)
	cast._begin(ClassDb.spell(11680))
	await get_tree().create_timer(0.5).timeout
	print("[animist] after release: pet ", pets.pet)
	get_tree().quit()
