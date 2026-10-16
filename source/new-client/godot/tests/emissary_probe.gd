extends Node
## Debug: the Krrzck emissary in Necht (Vigilant Rock) and the faction stable master beside him.
##   --headless --skip-login --zone=186 --figure=cel_m --ui-test --probe=emissary_probe
## Talk to Zrrazk (refused: aggro 100), talk to Kzzirrak, take a hunt, reroll, kill 10 of the target (simulated
## credited kills), claim; check the faction moved and Zrrazk now deals with you at -50 or better.
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var npcs = viewer.npcs
	var em: NpcState = null
	var stable: NpcState = null
	for s in npcs.states:
		var st: NpcState = s
		if String(st.spawn.name) == "Kzzirrak":
			em = st
		elif String(st.spawn.name) == "Zrrazk":
			stable = st
	print("[emissary] Kzzirrak ", em != null, " Zrrazk ", stable != null)
	if em == null or stable == null:
		get_tree().quit()
		return
	print("[emissary] apart: ", snappedf(em.pos.distance_to(stable.pos) / 0.025, 1.0), " units; Krrzck aggro ", PlayerData.faction_aggro(89))
	viewer.player.global_position = em.pos + Vector3(2, 0.3, 0)
	await get_tree().create_timer(1.5).timeout
	var vs: Npc = stable.view
	var ve: Npc = em.view
	print("[emissary] views ", vs != null, " ", ve != null)
	npcs.interact(vs)
	npcs.interact(ve)
	await get_tree().process_frame
	PlayerData.level = 30
	var e := Emissaries.mine()
	print("[emissary] pool at 30: ", Emissaries.pool(e, 30, "").map(func(c): return "%s %d" % [c.name, c.level]))
	print("[emissary] pool at 1: ", Emissaries.pool(e, 1, "").map(func(c): return "%s %d" % [c.name, c.level]))
	print("[emissary] pool at 50: ", Emissaries.pool(e, 50, "").map(func(c): return "%s %d" % [c.name, c.level]))
	viewer.emissaries._assign(e, false, "")
	print("[emissary] hunt: ", Emissaries.hunt())
	viewer.emissaries._assign(e, true, String(Emissaries.hunt().target))
	print("[emissary] rerolled: ", Emissaries.hunt().target, " gain ", Emissaries.gain())
	npcs.interact(ve)
	var target := String(Emissaries.hunt().target)
	var fake: NpcState = null                              # a real monster standing in for the kills
	for s in npcs.states:
		if int((s as NpcState).spawn.realm) == 0:
			fake = s
			break
	fake.spawn = {"name": target, "realm": 0}
	for i in 10:
		viewer.emissaries.on_kill(fake)
	print("[emissary] ready ", Emissaries.is_ready(), " ", Emissaries.journal_text())
	npcs.interact(ve)
	for k in 12:                                           # enough turn-ins to reach -50 (from 100, +5 or +10 each)
		if k > 0:
			viewer.emissaries._assign(e, false, "")
			for i in 10:
				fake.spawn = {"name": String(Emissaries.hunt().target), "realm": 0}
				viewer.emissaries.on_kill(fake)
		viewer.emissaries._claim(ve, e)
	print("[emissary] Krrzck aggro now ", PlayerData.faction_aggro(89), " ", PlayerData.faction_standing(89))
	npcs.interact(vs)
	await get_tree().process_frame
	get_tree().quit()
