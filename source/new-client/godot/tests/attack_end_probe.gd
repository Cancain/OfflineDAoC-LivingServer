extends Node
## Debug (owner 2026-10-14: attack mode doesn't end when the target dies): on a test server run, attack mode on the
## nearest monster in Lough Derg, which a damage over time then kills (/cast spell 23001 again until it dies) - how the
## death came (a health update / removed dead) and whether attack mode and the battle music ended; then the window
## closes itself.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(8.0)
	Server.command("/jump to 335142 516409 4791 200")
	await _wait(14.0)
	v = get_tree().current_scene
	var sw: ServerWorld = v.npcs
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind == "remove" and int(d.get("type", 1)) == 0:
			print("[attack] removed dead: ", d.oid)
		elif kind == "attack_mode":
			print("[attack] server attack mode: ", d.on))
	var mob: NpcState = null
	for st in sw.by_oid.values():
		var s: NpcState = st
		if s.view and s.alive and int(s.spawn.realm) == 0 and (mob == null or
				s.pos.distance_to(v.player.global_position) < mob.pos.distance_to(v.player.global_position)):
			mob = s
	if mob == null:
		print("[attack] no monster")
		get_tree().quit()
		return
	print("[attack] target ", mob.spawn.name, " oid ", mob.oid if "oid" in mob else "?")
	sw.select(mob.view)
	await _wait(1.0)
	v._toggle_attack()
	await _wait(1.0)
	print("[attack] attack on: ", v._server_attack)
	for i in 12:
		if not mob.alive:
			break
		Server.command("/cast spell 23001")
		await _wait(4.0)
		print("[attack]   health ", mob.health, " alive ", mob.alive, "  attack on ", v._server_attack)
	await _wait(2.0)
	print("[attack] after the death: alive ", mob.alive, "  attack on ", v._server_attack, "  battle music ",
			("playing" if v.audio._battle and v.audio._battle.playing else "stopped") if v.audio else "-")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
