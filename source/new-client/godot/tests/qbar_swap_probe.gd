extends Node
## Debug, local (owner 2026-10-14: a spell dropped on a filled quickbar slot replaced it and the old one was gone):
## a slot given A, then B dropped on it - B in the slot, A on the mouse pointer (the drag going on). Runs once, quits.
func _ready() -> void:
	if get_tree().root.has_meta("qbar_probe_ran"):
		return
	get_tree().root.set_meta("qbar_probe_ran", true)
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var slot: Control = null
	for c in v.ui.root.find_children("*", "", true, false):
		if c.has_method("_drop_data") and c.has_method("entry") and c.has_method("_hold"):
			slot = c
			break
	var a := {"kind": "macro", "id": "/say A", "icon": -1, "name": "AAA", "border": -1}
	slot._assign(a)
	slot._drop_data(Vector2.ZERO, {"kind": "macro", "id": "/say B", "icon": -1, "name": "BBB", "border": -1})
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport()
	print("[qb] slot now %s; dragging %s, on the pointer %s" % [slot.entry().get("name"), vp.gui_is_dragging(),
			(vp.gui_get_drag_data() as Dictionary).get("entry", {}).get("name") if vp.gui_get_drag_data() is Dictionary else "-"])
	slot._assign({})
	get_tree().quit()
