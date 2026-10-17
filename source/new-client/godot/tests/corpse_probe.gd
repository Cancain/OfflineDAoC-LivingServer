extends Node
## Debug: the server-death path offline - a nearby NPC's creature sounds (attack, pain, die, evade), every weapon
## sound set's swing / hits, then Npc.make_corpse (death pose, lies, sinks, frees itself).
##   --headless -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=corpse_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var n: Npc = null
	var with_sounds := 0
	for i in v.npcs.active:
		var a: Npc = v.npcs.active[i]
		if a.sounds:
			with_sounds += 1
			if n == null and a.state.alive:
				n = a
	print("[corpse] active views ", v.npcs.active.size(), " with sounds ", with_sounds)
	if n == null:
		get_tree().quit()
		return
	for k in ["attack", "pain_light", "pain_medium", "pain_heavy", "evade"]:
		n.sounds.event(k)
	for ws in range(1, 26):
		for k in ["use", "hit_light", "hit_medium", "parried", "blocked"]:
			n.sounds.weapon(ws, k)
	print("[corpse] sounds played on ", n.spawn.name)
	var y0 := n.global_position.y
	n.state.alive = false
	n.make_corpse()
	v.npcs.active.erase(n.state.index)
	var ref: WeakRef = weakref(n)
	await get_tree().create_timer(Npc.CORPSE_S + 1.0).timeout
	print("[corpse] sinking: y ", (ref.get_ref() as Npc).global_position.y if ref.get_ref() else -999.0, " from ", y0)
	await get_tree().create_timer(Npc.SINK_S + 1.0).timeout
	print("[corpse] freed: ", ref.get_ref() == null)
	get_tree().quit()
