extends Node
## Debug (owner 2026-10-14: the concentration window): Claude's GM test character casts Enhanced Blow (concentration),
## then cancels it from the window's list (RemoveConcentrationEffect, as Shift + right-click does).
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	(v.npcs as ServerWorld).clear_target()
	Server.command("/cast spell 3203")
	await _wait(2.5)
	print("[conc] after the cast: left ", Server.conc_left, "/", Server.max_conc, "  list ", Server.conc_list.map(func(e): return e.name))
	print("[conc] the client can cancel: ", Server.client.has_method("RemoveConcentration"))
	if not Server.conc_list.is_empty():
		Server.client.call("RemoveConcentration", int(Server.conc_list[0].index))
		await _wait(2.5)
	print("[conc] after cancelling: left ", Server.conc_left, "/", Server.max_conc, "  list ", Server.conc_list.map(func(e): return e.name),
			"  effects ", Server.effects_list().map(func(e): return e.name))
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
