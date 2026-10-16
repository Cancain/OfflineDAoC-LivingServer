extends Node
## Debug (owner 2026-10-14: the spell tab, baseline and spec lines, as the old client): on a test server run, the magic
## sheet with every line closed, then a baseline and a spec line clicked open (user://magic_tree_<n>.png).
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(8.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	for i in Server.spell_lines.size():
		print("[magic] line %d %s (%d spells)" % [i, Server.spell_lines[i].name, Server.spell_lines[i].spells.size()])
	v.ui.show_sheet("magic")
	await _shot(0)
	var n := Server.spell_lines.size()
	for li in ([0, n / 2] if n > 1 else [0]):
		var row := _row_of(String(Server.spell_lines[li].name))
		print("[magic] click ", Server.spell_lines[li].name, " row ", row)
		if row:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			row.gui_input.emit(ev)
	await _shot(1)
	get_tree().quit()


func _row_of(name: String) -> Control:
	for l in get_tree().root.find_children("*", "Label", true, false):
		if (l as Label).text.to_lower() == name.to_lower() and (l as Label).is_visible_in_tree() \
				and (l.get_parent() as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			return l.get_parent() as Control
	return null


func _shot(n: int) -> void:
	await _wait(0.8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://magic_tree_%d.png" % n)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
