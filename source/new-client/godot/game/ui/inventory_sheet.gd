class_name InventorySheet
extends RefCounted
## The INVENTORY sheet of the right panel, on the client's OLD grey-stone paper doll (data/skin1/pperdoll.bmp ->
## old_pperdoll, 192x448; owner 2026-10-09: the period grey-stone page). Coordinates measured on that bitmap:
##   equipment slots in the art's own boxes, your figure between them, the backpack list (8 rows, one sack at a
##   time), the 5 sack buttons, the money row (M P G S C).
## The bitmap also paints a MYTHICAL slot (added in 1.97): it is covered with the panel's own stone (UI BUILD PLAN.md).
## Drag and drop:
##   backpack row / slot -> equipment slot: equip (only where the item fits; swapped with what was there)
##   anything -> the figure: equip in the first slot that fits
##   equipment slot -> backpack row: take off; backpack row -> row: move / swap / stack; item -> sack button: into that
##   sack's first free row; item -> quickbar: a quickbar shortcut (the item stays here)
##   right-click: select the item (highlighted); then Shift+I = its details in the information window (the client's
##   Information/Delve key; period: "if you right click an item, type Shift-I to see the properties"), U = use it
##   double-click: equip from the backpack, take off from an equipment slot; hover: the item's name
##   left click (no drag): the item is "attached to your cursor" (1.64 manual) until the next left click places it -
##   on a slot, the merchant window (sells), the world; right-click or Esc puts it back (owner 2026-10-15: "left click
##   should lift up an item in the inventory until its placed not having to hold")

# slot id -> Rect2 in old_pperdoll pixels (the art's boxes)
const SLOTS := {
	25: Rect2(7, 36, 31, 31), 21: Rect2(155, 36, 31, 31),            # torso, helm
	29: Rect2(41, 36, 15, 15), 26: Rect2(137, 36, 15, 15),           # neck, cloak
	28: Rect2(7, 75, 31, 31), 22: Rect2(155, 75, 31, 31),            # arms, hands
	24: Rect2(7, 116, 15, 15), 32: Rect2(171, 116, 15, 15),          # jewelry, waist
	35: Rect2(7, 143, 15, 15), 36: Rect2(171, 143, 15, 15),          # left / right ring
	33: Rect2(7, 170, 15, 15), 34: Rect2(171, 170, 15, 15),          # left / right wrist
	27: Rect2(7, 196, 31, 27), 23: Rect2(155, 196, 31, 27),          # legs, feet
	10: Rect2(14, 234, 32, 31), 11: Rect2(58, 234, 31, 31),          # right hand, left hand
	12: Rect2(102, 234, 32, 31), 13: Rect2(146, 234, 31, 31),        # two handed, ranged
	37: Rect2(88, 36, 15, 15),                                        # the mythical slot (teleport necklaces ...): its
																	# box alone, top middle, no caption (owner 2026-10-15)
}
const DOLL := Rect2(42, 54, 108, 156)                               # between the slot columns
const WEIGHT_BOX := Rect2(42, 214, 56, 13)                          # the empty box under the doll: weight x / y
const ROW_Y := 277.75
const ROW_H := 16.86
const SACK_Y := [287, 313, 339, 364.5, 389.5]
const LETTER_X := [6, 46, 85, 124, 162]                             # the painted M P G S C
const COINS := ["mithril", "platinum", "gold", "silver", "copper"]

static var sack := 0


static func build(parent: Control, ui: GameUI) -> void:
	# cover the post-1.65 MYTHICAL box + caption with the plain stone right below it (same columns, so the panel's
	# lighter-in-the-middle shading matches; the first try copied the dark edge and showed as a patch)
	var stone := UiArt.picture("old_pperdoll", Rect2(62, 56, 70, 18))
	stone.position = Vector2(62, 34)
	parent.add_child(stone)
	var box := UiArt.picture("old_pperdoll", Rect2(72, 36, 15, 15))   # the art's own box, moved to the middle
	box.position = SLOTS[37].position
	parent.add_child(box)
	var doll := DollView.new()
	doll.position = DOLL.position
	doll.size = DOLL.size
	parent.add_child(doll)
	doll.build()
	for s in SLOTS:
		var w := EquipSlot.new()
		w.slot = s
		w.position = SLOTS[s].position
		w.size = SLOTS[s].size
		parent.add_child(w)
	for i in PlayerData.SACK:
		var r := BackpackRow.new()
		r.row = i
		r.position = Vector2(10, ROW_Y + i * ROW_H)
		r.size = Vector2(158, 16)
		parent.add_child(r)
	for i in 5:
		var b := SackButton.new()
		b.index = i
		b.position = Vector2(172, SACK_Y[i])
		b.size = Vector2(15, 15)
		parent.add_child(b)
	for i in 5:
		var l := UiArt.label("0", 8, UiArt.CREAM)
		l.name = "coin_" + COINS[i]
		l.position = Vector2(LETTER_X[i] + 9, 433)
		l.size = Vector2(28, 11)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.tooltip_text = COINS[i].to_upper()
		parent.add_child(l)
	var weight := UiArt.label("", 8, UiArt.CREAM)         # the weight box under the doll: carried / capacity
	weight.name = "weight"
	weight.position = WEIGHT_BOX.position
	weight.size = WEIGHT_BOX.size
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weight.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weight.mouse_filter = Control.MOUSE_FILTER_STOP
	weight.tooltip_text = "WEIGHT CARRIED / CARRYING CAPACITY"
	parent.add_child(weight)
	var refresh := func():
		var wl := parent.get_node_or_null("weight") as Label
		if wl:
			if Server.active:
				wl.text = "%d/%d" % [Server.weight_now, Server.weight_max] if Server.weight_max >= 0 else ""
			elif PlayerData.stats.size() >= 8:
				wl.text = "%d/%d" % [PlayerData.inventory_weight(), maxi(int(PlayerData.effective_stats()[0]), int(PlayerData.stats[0]))]
		for i in 5:
			var c := parent.get_node_or_null("coin_" + COINS[i])
			if c:
				c.text = str(PlayerData.money[COINS[i]])
		for c in parent.get_children():
			if c.has_method("refresh"):
				c.refresh()
	PlayerData.inventory_changed.connect(refresh)
	parent.tree_exiting.connect(func(): PlayerData.inventory_changed.disconnect(refresh))
	refresh.call()


static func drag_data(slot: int, from: Control) -> Variant:
	var e := PlayerData.entry(slot)
	if e.is_empty():
		return null
	from.set_drag_preview(_preview(slot, from))
	return _data(slot)


static func _data(slot: int) -> Dictionary:
	var e := PlayerData.entry(slot)
	var it := ItemDb.item(String(e.id))
	return {"kind": "item", "slot": slot, "id": String(e.id), "icon": int(it.get("icon", 0)), "name": String(it.get("name", ""))}


static func _preview(slot: int, from: Control) -> Control:
	var it := ItemDb.item(String(PlayerData.entry(slot).id))
	var prev := TextureRect.new()
	prev.texture = ItemDb.icon(int(it.get("icon", 0)))
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.size = Vector2(32, 32) * from.get_global_transform().get_scale()
	prev.modulate.a = 0.85
	return prev


## Click to pick up: a left press and release on an item without dragging puts it on the mouse pointer (a forced drag,
## as the quickbar's replaced spell) - Godot ends a forced drag at the next left PRESS, dropping it on what is under
## the pointer. Call from _gui_input; true when the event was the pick-up click.
static var held_at := 0                     # when the last click picked an item up (its double-click, below)


static func click_hold(c: Control, event: InputEvent, slot: int) -> bool:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.pressed:
		c.set_meta("click_press", not event.double_click and not PlayerData.entry(slot).is_empty())
		return false
	var was: bool = c.get_meta("click_press", false)
	c.set_meta("click_press", false)
	if not was or c.get_viewport().gui_is_dragging():
		return false
	_hold.call_deferred(c, slot)
	return true


static func _hold(c: Control, slot: int) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree() or c.get_viewport().gui_is_dragging() \
			or PlayerData.entry(slot).is_empty():
		return
	held_at = Time.get_ticks_msec()
	if "_dragged_slot" in c:
		c.set("_dragged_slot", slot)                    # (a click on the world drops it there, as a drag)
	c.force_drag(_data(slot), _preview(slot, c))


## A held item put down on the slot it came from: the second click of a double-click (the click picked it up, the
## forced drag's drop took the second press) - true then, so the slot does its double-click; later just put back.
static func double_clicked() -> bool:
	return Time.get_ticks_msec() - held_at < 500


## Whether the mouse is over the interface (an item let go there stays in it, not on the world): any control under it
## except the world's drop catcher and full-screen layers (those cover the world itself).
static func over_window(vp: Viewport) -> bool:
	var c := vp.gui_get_hovered_control()
	if c == null or c is GameUI.WorldDrop:
		return false
	var screen := vp.get_visible_rect().size
	var r := c.get_global_rect()
	return not (r.size.x >= screen.x * 0.95 and r.size.y >= screen.y * 0.95)


## A poison dropped on a weapon you wear: the server applies it (GamePlayerInventory.CheckPoisonApplication - the
## client's way: "drag the poison onto the weapon"; owner 2026-10-15: poisons for the poison classes). Server game only:
## the move goes to the server, which puts the poison on the blade and the vial back.
const POISON := 46                          # eObjectType.Poison


static func poison_on_weapon(it: Dictionary, slot: int) -> bool:
	return Server.active and int(it.get("object_type", 0)) == POISON and slot in [10, 11, 12, 13] 			and not PlayerData.item_at(slot).is_empty()


static func is_item(data: Variant) -> bool:
	return data is Dictionary and String(data.get("kind", "")) == "item" and data.has("slot")


## An equipment slot over the art's own box: the item's icon, gold rim while a fitting item hovers over it.
class EquipSlot extends Control:
	var slot := 0
	var _icon: TextureRect
	var _rim: Panel

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_rim = Panel.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0)
		s.border_color = UiArt.GOLD_HI
		s.set_border_width_all(1)
		_rim.add_theme_stylebox_override("panel", s)
		_rim.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rim.visible = false
		add_child(_rim)

	func refresh() -> void:
		var it := PlayerData.item_at(slot)
		_icon.texture = ItemDb.icon(int(it.get("icon", 0))) if not it.is_empty() else null
		var active: bool = {"standard": slot == 10, "twohand": slot == 12, "ranged": slot == 13}.get(PlayerData.active_weapon, false)
		_rim.visible = (active or PlayerData.selected_slot == slot) and not it.is_empty()
		tooltip_text = String(it.name).to_upper() if not it.is_empty() else String(PlayerData.SLOT_NAMES.get(slot, "")).to_upper()

	func _get_drag_data(_p: Vector2) -> Variant:
		return InventorySheet.drag_data(slot, self)

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		# the server's game: any item may be tried on a slot - the server decides (GamePlayerInventory's slot checks, its
		# own refusal message), as the old client let you try
		var ok := InventorySheet.is_item(data) and (int(data.slot) == slot or PlayerData.can_hold(slot, ItemDb.item(String(data.id)))
				or InventorySheet.poison_on_weapon(ItemDb.item(String(data.id)), slot) or Server.active)
		_rim.visible = ok
		return ok

	func _drop_data(_p: Vector2, data: Variant) -> void:
		if int(data.slot) == slot:                          # put back where it was (a double-click: taken off)
			if InventorySheet.double_clicked():
				PlayerData.unequip(slot)
			return
		PlayerData.move(int(data.slot), slot)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER and Server.active:
			Server.prefetch_item(slot)                     # the server's delve text, ready for the hover box
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			refresh()

	func _make_custom_tooltip(_for_text: String) -> Object:      # weapons / armour: the mini delve box
		return ItemTooltip.make(PlayerData.item_at(slot))


	func _gui_input(event: InputEvent) -> void:
		if InventorySheet.click_hold(self, event, slot):
			accept_event()
			return
		if event is InputEventMouseButton and event.pressed and not PlayerData.entry(slot).is_empty():
			if event.button_index == MOUSE_BUTTON_RIGHT:
				PlayerData.select_slot(slot)                # then Shift+I (delve) / U (use), as the client
				accept_event()
			elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				PlayerData.unequip(slot)
				accept_event()


## One backpack row: a small icon in the art's round box and the item's name (stack count after it).
class BackpackRow extends Control:
	var row := 0
	var _icon: TextureRect
	var _name: Label
	var _hi: ColorRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_hi = ColorRect.new()
		_hi.color = Color(1.0, 0.8, 0.35, 0.16)
		_hi.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hi.visible = false
		add_child(_hi)
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.position = Vector2(2.5, 0.5)
		_icon.size = Vector2(15, 15)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_name = UiArt.label("", 8, UiArt.CREAM)
		_name.position = Vector2(22, 1)
		_name.size = Vector2(128, 14)
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name.clip_text = true
		add_child(_name)

	func slot() -> int:
		return PlayerData.BACKPACK + InventorySheet.sack * PlayerData.SACK + row

	func refresh() -> void:
		var e := PlayerData.entry(slot())
		var it := ItemDb.item(String(e.id)) if not e.is_empty() else {}
		_icon.texture = ItemDb.icon(int(it.get("icon", 0))) if not it.is_empty() else null
		var n := String(it.get("name", "")).to_upper()
		if not e.is_empty() and int(e.get("count", 1)) > 1:
			n += " (%d)" % int(e.count)
		_name.text = n
		_hi.visible = PlayerData.selected_slot == slot() and not e.is_empty()
		tooltip_text = String(it.get("name", "")).to_upper()

	var _dragged_slot := -1                     # the slot this row started a drag from (its drop on the world, below)

	func _get_drag_data(_p: Vector2) -> Variant:
		_dragged_slot = slot()
		return InventorySheet.drag_data(slot(), self)

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		var ok := InventorySheet.is_item(data)
		_hi.visible = ok and int(data.slot) != slot()
		return ok

	func _drop_data(_p: Vector2, data: Variant) -> void:
		if int(data.slot) == slot():                        # put back where it was (a double-click: equipped)
			if InventorySheet.double_clicked():
				PlayerData.equip(slot())
			return
		PlayerData.move(int(data.slot), slot())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER and Server.active:
			Server.prefetch_item(slot())                   # the server's delve text, ready for the hover box
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			_hi.visible = false
		if what == NOTIFICATION_DRAG_END and _dragged_slot >= 0:
			var from := _dragged_slot
			_dragged_slot = -1
			# let go with nothing in the interface taking it and not over a window: dropped on the world (an NPC under
			# it, else the ground at your feet) - the world's drop catcher alone missed it (owner 2026-10-11: the
			# starting trimmed branch couldn't be dragged out of the inventory)
			if not get_viewport().gui_is_drag_successful() and not InventorySheet.over_window(get_viewport()):
				var scene := get_tree().current_scene
				var ui = scene.get("ui") if scene else null
				if ui and ui.has_signal("item_dropped_on_world"):
					ui.item_dropped_on_world.emit(from, get_viewport().get_mouse_position())

	func _make_custom_tooltip(_for_text: String) -> Object:      # weapons / armour: the mini delve box
		return ItemTooltip.make(PlayerData.item_at(slot()))


	func _gui_input(event: InputEvent) -> void:
		if InventorySheet.click_hold(self, event, slot()):
			accept_event()
			return
		if event is InputEventMouseButton and event.pressed and not PlayerData.entry(slot()).is_empty():
			if event.button_index == MOUSE_BUTTON_RIGHT:
				PlayerData.select_slot(slot())
				accept_event()
			elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				PlayerData.equip(slot())
				accept_event()


## A sack button over the art's sack: click to show that sack, drop an item on it to put it in that sack.
class SackButton extends Control:
	var index := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func refresh() -> void:
		var used := 0
		for i in PlayerData.SACK:
			if PlayerData.inventory.has(PlayerData.BACKPACK + index * PlayerData.SACK + i):
				used += 1
		tooltip_text = "SACK %d  (%d / %d)" % [index + 1, used, PlayerData.SACK]
		queue_redraw()

	func _draw() -> void:
		if index == InventorySheet.sack:
			draw_rect(Rect2(Vector2.ZERO, size), UiArt.GOLD_HI, false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			InventorySheet.sack = index
			PlayerData.inventory_changed.emit()
			accept_event()

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		return InventorySheet.is_item(data)

	func _drop_data(_p: Vector2, data: Variant) -> void:
		for i in PlayerData.SACK:
			var s := PlayerData.BACKPACK + index * PlayerData.SACK + i
			if not PlayerData.inventory.has(s):
				PlayerData.move(int(data.slot), s)
				return
		PlayerData.message.emit("That sack is full.", "error")


## Your character in the arch: the same Catacombs figure as in the world, idle, in its own small 3D world. Drag the
## figure sideways to turn it; drop an item on it to wear it.
class DollView extends Control:
	var _vp: SubViewport
	var _pivot: Node3D
	var _turn := false

	func build() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_vp = SubViewport.new()                    # rendered at 4x the arch's pixels, shown scaled like the art
		_vp.size = Vector2i(size * 4.0)
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(_vp)
		var view := TextureRect.new()
		view.texture = _vp.get_texture()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
		_vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, 25, 0)
		sun.light_energy = 1.1
		_vp.add_child(sun)
		var cam := Camera3D.new()
		cam.fov = 30
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3(0, 0.95, 4.2)
		_vp.add_child(cam)
		cam.look_at(Vector3(0, 0.92, 0))
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		var c := PlayerData.character
		var prefix := String(c.get("prefix", ""))
		if prefix != "":
			var f := Fig3Figure.new()
			_pivot.add_child(f)
			if f.load_figure(prefix):
				f.apply(c.get("look", {}) if c.get("look") is Dictionary else {})
				_figure = f
				_dress()
				PlayerData.inventory_changed.connect(_dress)
				tree_exiting.connect(func():
					if PlayerData.inventory_changed.is_connected(_dress):
						PlayerData.inventory_changed.disconnect(_dress))
		_pivot.rotation.y = deg_to_rad(15)
		_fit.call_deferred()

	var _figure: Fig3Figure
	var _gear: Array = []

	## What you wear on the doll too (armour with its dyes, the weapons), as on your character in the world.
	func _dress() -> void:
		if _figure == null or not is_instance_valid(_figure):
			return
		for g in _gear:
			if is_instance_valid(g):
				g.queue_free()
		_gear = Player.dress(_figure, PlayerData.item_at, PlayerData.active_weapon, false, true,
				PlayerData.character.get("gear", {}) if PlayerData.character.get("gear") is Dictionary else {})

	## Every race and size fills the arch the same (owner 2026-10-09: the male troll was cut off): the figure's real
	## height (visible meshes, its race scale and Short / Average / Tall) is scaled to one height the camera frames.
	const FIT_HEIGHT := 1.85

	func _fit() -> void:
		if not is_inside_tree():
			return
		await get_tree().process_frame                     # transforms and the figure's own scale settled
		_pivot.scale = Vector3.ONE
		var lo := INF
		var hi := -INF
		for mi in _pivot.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not m.is_visible_in_tree() or m.mesh == null:
				continue
			var box: AABB = _pivot.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			lo = minf(lo, box.position.y)
			hi = maxf(hi, box.end.y)
		if hi > lo:
			var k := FIT_HEIGHT / (hi - lo)
			_pivot.scale = Vector3.ONE * k
			_pivot.position.y = -lo * k                     # feet on the floor line whatever the scale

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_turn = event.pressed
		elif event is InputEventMouseMotion and _turn:
			_pivot.rotation.y += event.relative.x * 0.02

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		return InventorySheet.is_item(data) and PlayerData.is_backpack(int(data.slot)) and \
				not PlayerData.slots_for(ItemDb.item(String(data.id))).is_empty()

	func _drop_data(_p: Vector2, data: Variant) -> void:
		PlayerData.equip(int(data.slot))
