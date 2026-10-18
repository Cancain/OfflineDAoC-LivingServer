extends Control
## Debug (owner 2026-10-17: the guild UI): the guild emblem picker alone, opened on a sample emblem -
## user://emblem_picker.png. Runs once.
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.2, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var holder := Control.new()
	holder.scale = Vector2(3, 3)
	add_child(holder)
	var w := EmblemWindow.new()
	w.setup("emblem_test", "emblempick", Rect2(), Vector2(20, 10))
	holder.add_child(w)
	w.build()
	w.open(Emblems.encode(8, 1, 0, 3))
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://emblem_picker.png")
	get_tree().quit()
