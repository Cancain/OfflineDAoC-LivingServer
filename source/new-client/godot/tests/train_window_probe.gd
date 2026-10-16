extends Node
## Debug (owner 2026-10-14: "/train doesn't properly open a trainer window remotely"): on a test server run, Claude's
## test character in the open (no trainer near) types /train - the trainer window and its lists - then TRAIN on the
## first specialization (the window's own button), its level before and after; the window closes itself.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	Server.command("/jump to 335142 516409 4791 200")       # Lough Derg's fields: no trainer near
	await _wait(14.0)
	v = get_tree().current_scene
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	v.ui.chat.run_line("/train")
	await _wait(2.0)
	var tw: TrainerWindow = v.ui.trainer
	print("[train] window open: ", tw.visible, "  spec rows ", tw._rows.get_child_count(), "  realm rows ",
			tw._ra_rows.get_child_count(), "  points box '", tw._points.text, "'")
	var spec := ""
	var before := -1
	for sk in Server.skills:
		if int(sk.page) == 0:
			spec = String(sk.name)
			before = int(sk.level)
			break
	if tw.visible and spec != "":
		tw._selected = spec
		for c in tw.get_children():
			if c is Button and (c as Button).text == "TRAIN":
				(c as Button).pressed.emit()
		await _wait(2.5)
		var after := -1
		for sk in Server.skills:
			if String(sk.name) == spec:
				after = int(sk.level)
		print("[train] TRAIN on ", spec, ": level ", before, " -> ", after, "  points box '", tw._points.text, "'")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://train_window.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
