extends Node
## Debug: charm. A level 30 Mentalist (Mentalism 30) charms a monster with its charm spell (pulsing: re-rolled every
## pulse), the monster joins as a pet; then the song is cancelled and the monster turns on the player.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=charm_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	PlayerData.level = 30
	PlayerData.promote(ClassDb.by_name("Mentalist"))
	for e in ClassDb.trainable_specs(PlayerData.class_id(), 30):
		PlayerData.specs[String(e.spec)] = 30
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	var charm := {}
	for line in ClassDb.spell_lines(PlayerData.class_id(), 30, PlayerData.specs):
		for sid in line.spells:
			var sp := ClassDb.spell(int(sid))
			if String(sp.get("type", "")) == "Charm":
				charm = sp
	print("[charm] spell ", charm.get("name"), " pulse ", charm.get("pulse"), " value ", charm.get("value"), " type ", charm.get("amnesiachance"))
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		var n := String(st.spawn.name)
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 10 and st.level <= 20 and n[0] == n[0].to_lower() \
				and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	print("[charm] target ", mob.spawn.name, " L", mob.level, " body ", mob.spawn.body_type)
	viewer.player.global_position = mob.pos + Vector3(8, 0.3, 0)
	await get_tree().create_timer(3.0).timeout
	if mob.view:
		viewer.npcs.select(mob.view)
	for tries in 4:
		cast._begin(charm)
		await get_tree().create_timer(float(charm.get("casttime", 0)) + 1.0).timeout
		if pets.pet == mob:
			break
	print("[charm] charmed ", pets.pet == mob, " realm ", mob.spawn.realm, " window ", PlayerData.pet)
	await get_tree().create_timer(12.0).timeout
	print("[charm] after 12 s still charmed ", pets.pet == mob)
	cast._begin(charm)                                       # cast again: the song stops
	await get_tree().create_timer(1.0).timeout
	print("[charm] after cancel: pet ", pets.pet, " realm ", mob.spawn.realm, " fighting ", mob.fighting, " aggro ", mob.aggro.values())
	get_tree().quit()
