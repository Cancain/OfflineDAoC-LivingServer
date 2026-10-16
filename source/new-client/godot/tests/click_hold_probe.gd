extends Node
## Debug, local (owner 2026-10-15: "left click should lift up an item in the inventory until its placed"): a click on a
## backpack row puts its item on the pointer, a click on an empty row puts it there, right-click puts a held item back.
## Clicks go in as real mouse events. Runs once, quits (hard stop 40 s).
##   --skip-login --zone=200 --figure=elf_m --ui-test --probe=click_hold_probe
var vp: Viewport


func _ready() -> void:
	if get_tree().root.has_meta("click_hold_ran"):
		return
	get_tree().root.set_meta("click_hold_ran", true)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	vp = get_viewport()
	await get_tree().create_timer(6.0).timeout
	v.ui.show_sheet("inventory")
	await _frames(3)
	var rows: Array = v.ui.root.find_children("*", "", true, false).filter(func(c): return c.has_method("slot") and c.has_method("_drop_data") and c.get("row") != null)
	print("[hold] backpack rows: %d" % rows.size())
	var full: Control = null
	var empty: Control = null
	for r in rows:
		if not PlayerData.entry(r.slot()).is_empty() and full == null:
			full = r
		elif PlayerData.entry(r.slot()).is_empty() and empty == null:
			empty = r
	if full == null and empty != null:                          # nothing carried: one item for the test (not saved)
		var id := ""
		for k in ItemDb.all_merchant_items():
			id = String(k[2]) if k is Array else String(k)
			if id != "" and not ItemDb.item(id).is_empty():
				break
		PlayerData.inventory[empty.slot()] = {"id": id, "count": 1}
		PlayerData.inventory_changed.emit()
		full = empty
		empty = null
		for r in rows:
			if r != full and PlayerData.entry(r.slot()).is_empty():
				empty = r
				break
	if full == null or empty == null:
		print("[hold] FAILED: no item row / empty row")
		get_tree().quit()
		return
	var a: int = full.slot()
	var b: int = empty.slot()
	var id := String(PlayerData.entry(a).id)
	print("[hold] item %s in slot %d, empty slot %d" % [ItemDb.item(id).get("name", id), a, b])
	await _click(full, MOUSE_BUTTON_LEFT)
	print("[hold] 1 after a click on it: on the pointer %s" % _held())
	await _move(empty)
	print("[hold] 2 moved away (no button): still on the pointer %s" % _held())
	await _click(empty, MOUSE_BUTTON_LEFT)
	print("[hold] 3 after a click on the empty row: on the pointer %s, item now in %d: %s, old slot empty: %s" % [
			_held(), b, String(PlayerData.entry(b).get("id", "")) == id, PlayerData.entry(a).is_empty()])
	await _click(empty, MOUSE_BUTTON_LEFT)
	print("[hold] 4 picked up again: %s" % _held())
	await _move(full)
	await _click(full, MOUSE_BUTTON_RIGHT)
	print("[hold] 5 right-click while held: on the pointer %s, still in %d: %s" % [_held(), b, String(PlayerData.entry(b).get("id", "")) == id])
	PlayerData.move(b, a)                                        # back where it was
	print("[hold] restored to slot %d: %s" % [a, String(PlayerData.entry(a).get("id", "")) == id])
	get_tree().quit()


func _held() -> String:
	var d = vp.gui_get_drag_data() if vp.gui_is_dragging() else null
	return "yes (slot %d)" % int(d.slot) if d is Dictionary and d.has("slot") else "no"


func _pos(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


func _move(c: Control) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _pos(c)
	m.global_position = m.position
	Input.parse_input_event(m)
	await _frames(3)


func _click(c: Control, button: MouseButton) -> void:
	await _move(c)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.position = _pos(c)
		e.global_position = e.position
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if (down and button == MOUSE_BUTTON_LEFT) else 0
		Input.parse_input_event(e)
		await _frames(3)
	await get_tree().create_timer(0.6).timeout                   # (past the double-click time)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
