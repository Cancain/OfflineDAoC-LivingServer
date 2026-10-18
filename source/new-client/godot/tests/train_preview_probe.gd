extends Node
## Debug (owner 2026-10-17: the training preview, shown in game): Claude's GM test character made a Champion (a hybrid
## with many lines), /train, then each of --specs=<n,...> (its place in the window) clicked and the window pictured
## (user://train_preview_<n>.png); its class put back at the end. Prints what the server sent.
var v: Node


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	await _wait(8.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	PlayerData.message.connect(func(t, _k):
		if "class" in String(t).to_lower() or "target" in String(t).to_lower():
			print("[chat] ", t))
	var cls := int(v.args.get("class", "0"))   # 0: keep the class
	var was := PlayerData.class_id()
	print("[train] class was ", was)
	Server.client.call("Target", Server.me_oid, 0x6000)
	await _wait(1.0)
	if cls > 0:
		Server.command("/player class %d" % cls)
	await _wait(4.0)
	print("[train] class now ", PlayerData.class_id())
	Server.client.call("TrainWindow")
	await _wait(3.0)
	var tw: TrainerWindow = v.ui.trainer
	if not tw.visible:
		tw.open()
	print("[train] specs ", Server.trainer_specs.size(), "  lists ", Server.trainer_skills.size())
	for sp in Server.trainer_specs:
		var list: Array = Server.trainer_skills.get(int(sp.index), [])
		print("[train]   ", sp.name, " lvl ", sp.level, ": ", list.size(), " skills; first ",
				list.slice(0, 3).map(func(k): return "%s@%d" % [k.get("name", "?"), int(k.level)]))
	for n in String(v.args.get("specs", "0")).split(","):
		var i := int(n)
		if i >= Server.trainer_specs.size():
			continue
		tw._selected = String(Server.trainer_specs[i].name)
		tw._selected_ra = -1
		tw.refresh()
		await _wait(0.8)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://train_preview_%d.png" % i)
		print("[train] pictured ", tw._selected)
	if was > 0 and v.args.has("restore"):                # (class_id reads a base class's id - 51 Magician for
		Server.command("/player class %d" % was)           # the Sluaghbinder; only with --restore)
	await _wait(2.0)
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
