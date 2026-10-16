extends Node
## Debug: the Necromancer. Level 30, all specs 30: summons its best servant (shade), can't melee, sends a PetSpell
## nuke through the servant at a monster (cast by the servant), then the servant is killed (shade ends, health cut).
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=necro_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	PlayerData.level = 30
	PlayerData.promote(ClassDb.by_name("Necromancer"))
	for e in ClassDb.trainable_specs(PlayerData.class_id(), 30):
		PlayerData.specs[String(e.spec)] = 30
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	var summon := {}
	var nuke := {}
	for line in ClassDb.spell_lines(PlayerData.class_id(), 30, PlayerData.specs):
		for sid in line.spells:
			var sp := ClassDb.spell(int(sid))
			if String(sp.type) == "SummonNecroPet":
				summon = sp
			if String(sp.type) == "PetSpell" and String(ClassDb.spell(int(sp.subspellid)).get("type", "")) == "DirectDamage":
				nuke = sp
	print("[necro] summon ", summon.get("name"), " nuke ", nuke.get("name"))
	pets.summon(summon, null)
	print("[necro] servant ", pets.pet.spawn.name, " L", pets.pet.level, " hp ", pets.pet.max_hp, " stats ", pets.pet.stats, " int ", pets.pet.spawn.intel, " shade ", viewer.player.shade)
	combat.set_attack_mode(true)
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 10 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	viewer.player.global_position = mob.pos + Vector3(12, 0.3, 0)
	await get_tree().create_timer(2.0).timeout
	pets.pet.pos = mob.pos + Vector3(3, 0, 0)                         # the servant stands by it (Channeled Fury: point blank)
	pets._b[pets.pet].walk = "stay"
	pets._b[pets.pet].stay = pets.pet.pos
	if mob.view:
		viewer.npcs.select(mob.view)
	cast._begin(nuke)
	await get_tree().create_timer(float(ClassDb.spell(int(nuke.subspellid)).get("casttime", 0)) + 1.0).timeout
	print("[necro] mob hp ", mob.hp)
	PlayerData.set_hp(PlayerData.max_hp)
	pets.pet.hp = int(pets.pet.max_hp * 0.3)
	pets.pet.health = 0.3
	pets.pet.damage(pets.pet.hp)                                     # the servant dies at 30% ... then 0
	await get_tree().create_timer(0.5).timeout
	print("[necro] after the servant: shade ", viewer.player.shade, " hp ", PlayerData.hp, "/", PlayerData.max_hp)
	get_tree().quit()
