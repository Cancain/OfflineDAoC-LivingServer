extends Node
## Debug (owner 2026-10-14: the trainer's Realm Skills empty): Claude's GM test Forester is made an Animist at Aslynav
## ([Path of Affinity]) and the trainer's window opened again - the Realm Skills rows the server sends, drawn
## (screenshot user://trainer_ra.png).
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	var sw: ServerWorld = v.npcs
	Server.command("/jump to 421492 487466 2336 200")     # beside Aslynav, Animist trainer
	await _wait(10.0)
	var tr: Npc = null
	for _i in 40:
		for st in sw.by_oid.values():
			if (st as NpcState).view and String((st as NpcState).spawn.name).to_lower() == "aslynav":
				tr = (st as NpcState).view
		if tr:
			break
		await _wait(0.5)
	if tr == null:
		print("[ra] no trainer")
		get_tree().quit()
		return
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	Server.client.call("Target", Server.me_oid, 0x6000)    # yourself, then the GM's class change (Forester -> Animist)
	await _wait(1.0)
	Server.command("/player class 55")
	await _wait(3.0)
	sw.select(tr)
	await _wait(0.5)
	sw.interact(tr)
	await _wait(3.0)
	print("[ra] window open: ", v.ui.trainer.visible, "  realm skills: ", Server.realm_abilities.size(), "  points ", Server.ra_points,
			"  rows drawn: ", v.ui.trainer._ra_rows.get_child_count(), "  pts box: ", v.ui.trainer._points.text)
	for ra in Server.realm_abilities.slice(0, 4):
		print("[ra]   ", ra)
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://trainer_ra.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
