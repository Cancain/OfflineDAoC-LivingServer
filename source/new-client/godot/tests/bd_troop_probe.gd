extends Node
## Debug (owner 2026-10-10: the commander controls its minions, they follow in formation): a Bonedancer 50 summons a
## Bone Commander, a Bone Watchman and a Bone Diviner, walks off - the minions' places in the commander's frame (line
## formation: 1.25 m / 2.5 m behind it) - then /formation triangle, then ATTACK on a monster (all three on it), then a
## monster blow on a minion (the whole troop takes it on), and a third minion refused (two slots).
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=bd_troop_probe
var viewer: Node


func _rel(pets: Pets, m: NpcState) -> String:
	var c := pets.pet
	var fwd := Vector3(sin(c.yaw), 0, cos(c.yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var d := m.pos - c.pos
	return "ahead %.2f m, right %.2f m" % [d.dot(fwd), d.dot(right)]


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var chat: Array = []
	PlayerData.message.connect(func(t, _k): chat.append(String(t)))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	PlayerData.level = 50
	PlayerData.promote(ClassDb.by_name("Bonedancer"))
	for k in ["Darkness", "Suppression", "Bone Army"]:
		PlayerData.specs[k] = 50
	PlayerData.recalc_max()
	for sid in [10103, 10055, 10005, 10056]:
		PlayerData.set_power(PlayerData.max_power)
		cast._begin(ClassDb.spell(sid))
		await get_tree().create_timer(7.0).timeout
	print("[troop] commander ", pets.pet.spawn.name if pets.pet else "none", " minions ", pets.minions.map(func(m): return "%s L%d" % [m.spawn.name, m.level]))
	print("[troop] chat: ", chat.filter(func(t): return "minion" in t or "followers" in t or "control" in t))
	if pets.pet == null or pets.minions.size() < 2:
		get_tree().quit()
		return
	viewer.player.global_position += Vector3(18, 0, 6)
	await get_tree().create_timer(8.0).timeout
	print("[troop] line: commander %.1f m from you; " % pets.pet.pos.distance_to(viewer.player.global_position),
			"; ".join(pets.minions.map(func(m): return _rel(pets, m))))
	PlayerData.pet_order.emit("formation:triangle")
	viewer.player.global_position += Vector3(-10, 0, 10)
	await get_tree().create_timer(8.0).timeout
	print("[troop] triangle: ", "; ".join(pets.minions.map(func(m): return _rel(pets, m))))
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and int(st.spawn.get("aggro_level", 0)) > 0 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 99999
	mob.hp = 99999
	viewer.player.global_position = mob.pos + Vector3(10, 0.3, 0)
	await get_tree().create_timer(3.0).timeout
	print("[troop] target ", mob.spawn.name, " view ", mob.view != null, " friendly ", (mob.view as Npc).is_friendly() if mob.view else "-")
	if mob.view:
		viewer.npcs.select(mob.view)
	PlayerData.pet_command("attack")
	await get_tree().create_timer(6.0).timeout
	print("[troop] attack: commander on ", pets._b[pets.pet].target.spawn.name if pets._b[pets.pet].target else "-",
			"; minions on ", pets.minions.map(func(m): return pets._b[m].target.spawn.name if pets._b[m].target else "-"))
	PlayerData.pet_command("passive")
	await get_tree().create_timer(1.0).timeout
	print("[troop] passive: modes ", [pets._b[pets.pet].mode] + pets.minions.map(func(m): return pets._b[m].mode))
	PlayerData.pet_command("defensive")
	var other: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st != mob and (other == null or st.pos.distance_to(viewer.player.global_position) < other.pos.distance_to(viewer.player.global_position)):
			other = st
	pets.npc_hits_pet(other, pets.minions[0])
	print("[troop] a blow on ", pets.minions[0].spawn.name, ": commander aggro on it ", pets._b[pets.pet].aggro.has(other),
			", other minion ", pets._b[pets.minions[1]].aggro.has(other))
	get_tree().quit()
