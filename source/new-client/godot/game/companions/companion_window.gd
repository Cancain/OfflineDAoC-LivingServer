class_name CompanionWindow
extends ClassicWindow
## A companion's window (bot plan phase 6): right-click your companion (or MANAGE at the innkeeper).
##   GEAR - what it wears (every 1.65 equipment slot) and its bag (10 slots, weightless): drag an item from your
##     backpack onto a slot to hand it over (only what its class can use at its level goes on - armour opens up as it
##     levels, as yours does); drag between its own slots; double-click (or right-click) one of its items to take it
##     back into your backpack.
##   TRAINING - its specializations: points to spend, TRAIN raises one (the trainer's rules: the next level costs
##     that many points, never past its level); realm abilities come with realm points.
##   TACTICS - what it uses, in order: the styles, spells and abilities it knows on the left, its bar of 10 on the
##     right (first that fits goes); click to add, click a bar slot to take it off, the arrows move the picked one;
##     KEEP BUFFS UP.
##   STANCE - aggressive / defensive / supportive / passive (owner 2026-10-11), each explained.
## Its health, power, endurance and experience along the top.

const SIZE := Vector2(450, 320)
const BOX := 22.0
const TACTIC_SLOTS := 10
const STANCE_TEXT := {
	"aggressive": "Attacks whatever you attack, and anything that attacks you, itself or the rest of your group. It never picks a fight on its own.",
	"defensive": "Fights only when you or another companion is attacked, or a monster comes within 300 units.",
	"supportive": "Heals and buffs first. Never fights with plain swings - only with the attacks you put on its tactics bar.",
	"passive": "Only heals and buffs. Never attacks, whatever its tactics bar holds."}

var companions: Companions
var id := -1
var _title: Label
var _status: Label
var _tabs: Array = []
var _pages: Array = []
var _slots: Array = []
var _specs: VBoxContainer
var _points: Label
var _avail: VBoxContainer
var _bar: Array = []
var _picked := -1
var _stance_buttons := {}
var _dismiss: Button
var _refresh_left := 0.0


func build() -> void:
	closable = true
	_title = CompanionUi.frame(self, "companion", SIZE, Vector2(220, 80), "COMPANION")
	_status = CompanionUi.text(self, "", Vector2(14, 17), Vector2(SIZE.x - 28, 12), 8, UiArt.GOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tabs = CompanionUi.tabs(self, ["Gear", "Training", "Tactics", "Stance"], Vector2(12, 31), SIZE.x - 24, show_page)
	for i in 4:
		var page := Control.new()
		page.position = Vector2(0, 50)
		page.size = Vector2(SIZE.x, SIZE.y - 76)
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(page)
		_pages.append(page)
	_build_gear(_pages[0])
	_build_training(_pages[1])
	_build_tactics(_pages[2])
	_build_stance(_pages[3])
	_dismiss = CompanionUi.button(self, "Dismiss to the inn", Vector2(SIZE.x - 146, SIZE.y - 22), Vector2(132, 15), func():
		if companions:
			companions.dismiss(id)
			hide_window(), 8)
	show_page(0)
	PlayerData.inventory_changed.connect(refresh)


func open_for(companion_id: int, comps: Companions) -> void:
	id = companion_id
	companions = comps
	if not companions.changed.is_connected(refresh):
		companions.changed.connect(refresh)
	_picked = -1
	show_window()
	refresh()


func _rec() -> Dictionary:
	return Companions.by_id(id)


func _sheet() -> CharacterState:
	return companions.edit_sheet(_rec()) if companions and not _rec().is_empty() else null


func show_page(i: int) -> void:
	for k in _pages.size():
		(_pages[k] as Control).visible = k == i
	CompanionUi.select_tab(_tabs, i)
	refresh()


func refresh() -> void:
	if not visible or companions == null:
		return
	var rec := _rec()
	var s := _sheet()
	if rec.is_empty() or s == null:
		hide_window()
		return
	var state := String(Companions.info(rec).get("state", ""))
	_title.text = ("%s - %s %d" % [rec.name, String(rec.get("class_name", "")), s.level]).to_upper()
	var lo := CombatRules.xp_for_level(s.level)
	var hi := CombatRules.xp_for_level(s.level + 1)
	_status.text = "HEALTH %d / %d    POWER %d / %d    ENDURANCE %d    EXPERIENCE %d%%%s" % [s.hp, s.max_hp, s.power_pts,
			s.max_power, s.end_pts, int(100.0 * (s.xp - lo) / maxf(1.0, hi - lo)), "    (DEAD)" if state == "dead" else ""]
	_dismiss.visible = state == "with"
	for b in _slots:
		(b as CompSlot).refresh()
	_refresh_training(s)
	_refresh_tactics(s)
	var stance := String(Companions.info(rec).get("stance", "aggressive"))
	for k in _stance_buttons:
		(_stance_buttons[k] as Button).button_pressed = k == stance


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0 and visible:
		_refresh_left = 1.0
		var s := _sheet()
		if s and _status:
			var lo := CombatRules.xp_for_level(s.level)
			var hi := CombatRules.xp_for_level(s.level + 1)
			_status.text = "HEALTH %d / %d    POWER %d / %d    ENDURANCE %d    EXPERIENCE %d%%" % [s.hp, s.max_hp, s.power_pts,
					s.max_power, s.end_pts, int(100.0 * (s.xp - lo) / maxf(1.0, hi - lo))]


# --- gear -------------------------------------------------------------------------------------------------------

func _build_gear(page: Control) -> void:
	CompanionUi.text(page, "WORN", Vector2(14, 0), Vector2(100, 12), 8, UiArt.GOLD)
	var slots := CharacterState.EQUIP_SLOTS.filter(func(x): return int(x) != 37)   # (the 3 x 6 grid: no mythical)
	for i in slots.size():
		var col := i / 6
		var row := i % 6
		var b := CompSlot.new()
		b.window = self
		b.slot = int(slots[i])
		b.position = Vector2(14 + col * 140, 14 + row * (BOX + 6))
		b.size = Vector2(BOX, BOX)
		page.add_child(b)
		_slots.append(b)
		CompanionUi.text(page, String(CharacterState.SLOT_NAMES.get(int(slots[i]), "")), b.position + Vector2(BOX + 4, 5), Vector2(110, 12), 7, CompanionUi.DIM)
	CompanionUi.text(page, "BAG (WEIGHTLESS)", Vector2(14, 188), Vector2(160, 12), 8, UiArt.GOLD)
	for i in Companions.BAG_SLOTS:
		var b := CompSlot.new()
		b.window = self
		b.slot = Companions.BAG_FIRST + i
		b.position = Vector2(14 + i * (BOX + 4), 202)
		b.size = Vector2(BOX, BOX)
		page.add_child(b)
		_slots.append(b)
	CompanionUi.text(page, "Drag items from your backpack onto a slot to hand them over; double-click one of its items to take it back.",
			Vector2(14, 228), Vector2(SIZE.x - 28, 20), 7, CompanionUi.DIM, true)


class CompSlot extends Control:
	var window: CompanionWindow
	var slot := 0
	var _icon: TextureRect
	var _rim: Panel

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_rim = Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.028, 0.025, 0.95)
		sb.border_color = UiArt.GOLD.darkened(0.5)
		sb.set_border_width_all(1)
		_rim.add_theme_stylebox_override("panel", sb)
		_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rim)
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)

	func refresh() -> void:
		_rim.size = size
		_icon.position = Vector2(2, 2)
		_icon.size = size - Vector2(4, 4)
		var s := window._sheet()
		var it := s.item_at(slot) if s else {}
		_icon.texture = ItemDb.icon(int(it.get("icon", 0))) if not it.is_empty() else null
		tooltip_text = String(it.get("name", "")).to_upper()

	func _make_custom_tooltip(_t: String) -> Object:
		var s := window._sheet()
		return ItemTooltip.make(s.item_at(slot)) if s and not s.item_at(slot).is_empty() else null

	func _get_drag_data(_p: Vector2) -> Variant:
		var s := window._sheet()
		if s == null or s.entry(slot).is_empty():
			return null
		var prev := TextureRect.new()
		prev.texture = _icon.texture
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.size = Vector2(28, 28) * get_global_transform().get_scale()
		set_drag_preview(prev)
		return {"kind": "comp_item", "slot": slot, "comp": window.id}

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		return InventorySheet.is_item(data) or (data is Dictionary and String(data.get("kind", "")) == "comp_item" and int(data.comp) == window.id)

	func _drop_data(_p: Vector2, data: Variant) -> void:
		if InventorySheet.is_item(data):
			window.companions.give_item(window.id, int(data.slot), slot)
		else:
			window.companions.move_item(window.id, int(data.slot), slot)
		window.refresh()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event.double_click or event.button_index == MOUSE_BUTTON_RIGHT):
			window.companions.take_item(window.id, slot)
			window.refresh()
			accept_event()


# --- training ---------------------------------------------------------------------------------------------------

func _build_training(page: Control) -> void:
	_points = CompanionUi.text(page, "", Vector2(14, 0), Vector2(SIZE.x - 28, 12), 8, UiArt.GOLD)
	var box := CompanionUi.inset(page, Vector2(12, 16), Vector2(SIZE.x - 24, 196))
	var sc := ScrollContainer.new()
	sc.position = Vector2(3, 3)
	sc.size = box.size - Vector2(6, 6)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_specs = VBoxContainer.new()
	_specs.custom_minimum_size = Vector2(sc.size.x - 10, 0)
	sc.add_child(_specs)
	CompanionUi.text(page, "Realm abilities: none to train yet - they come with realm points.", Vector2(14, 218), Vector2(SIZE.x - 28, 12), 7, CompanionUi.DIM)


func _refresh_training(s: CharacterState) -> void:
	_points.text = "SPECIALIZATION POINTS TO SPEND: %d" % s.spec_points()
	for c in _specs.get_children():
		c.queue_free()
	for e in ClassDb.trainable_specs(s.class_id(), s.level):
		var key := String(e.spec)
		var row := Control.new()
		row.custom_minimum_size = Vector2(_specs.custom_minimum_size.x, 20)
		var lv := int(s.specs.get(key, 1))
		CompanionUi.text(row, String(ClassDb.spec(key).get("name", key)), Vector2(4, 4), Vector2(170, 12), 8)
		CompanionUi.text(row, str(lv), Vector2(180, 4), Vector2(30, 12), 9, UiArt.GOLD_HI)
		var cost := lv + 1
		CompanionUi.text(row, "NEXT LEVEL: %d PTS" % cost if lv < s.level else "AT ITS LEVEL", Vector2(212, 4), Vector2(96, 12), 7,
				CompanionUi.DIM)
		var b := CompanionUi.button(row, "Train", Vector2(310, 2), Vector2(56, 15), func():
			companions.train(id, key)
			refresh(), 8)
		b.disabled = lv >= s.level or s.spec_points() < cost
		_specs.add_child(row)


# --- tactics ----------------------------------------------------------------------------------------------------

func _build_tactics(page: Control) -> void:
	CompanionUi.text(page, "KNOWS (CLICK TO ADD)", Vector2(14, 0), Vector2(110, 12), 8, UiArt.GOLD)
	var hide := UiArt.button("Hide lower ranks", Vector2(102, 13), 7)
	hide.toggle_mode = true
	hide.position = Vector2(124, -1)
	var cfg := ConfigFile.new()
	cfg.load(UiArt.settings_path)
	_hide_lower = bool(cfg.get_value("companions", "hide_lower_ranks", false))
	hide.button_pressed = _hide_lower
	hide.toggled.connect(func(on: bool):
		_hide_lower = on
		var c2 := ConfigFile.new()
		c2.load(UiArt.settings_path)
		c2.set_value("companions", "hide_lower_ranks", on)
		c2.save(UiArt.settings_path)
		refresh())
	page.add_child(hide)
	var box := CompanionUi.inset(page, Vector2(12, 14), Vector2(214, 214))
	var sc := ScrollContainer.new()
	sc.position = Vector2(3, 3)
	sc.size = box.size - Vector2(6, 6)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_avail = VBoxContainer.new()
	_avail.custom_minimum_size = Vector2(sc.size.x - 10, 0)
	_avail.add_theme_constant_override("separation", 1)
	sc.add_child(_avail)
	CompanionUi.text(page, "TACTICS - FIRST THAT FITS IS USED", Vector2(236, 0), Vector2(204, 12), 8, UiArt.GOLD)
	for i in TACTIC_SLOTS:
		var b := UiArt.button("", Vector2(178, 15), 8)
		b.position = Vector2(236, 14 + i * 17)
		var idx := i
		b.pressed.connect(func(): _bar_clicked(idx))
		page.add_child(b)
		_bar.append(b)
		CompanionUi.text(page, str(i + 1), Vector2(418, 16 + i * 17), Vector2(20, 12), 8, CompanionUi.DIM)
	CompanionUi.button(page, "Up", Vector2(236, 186), Vector2(56, 15), func(): _move_picked(-1), 8)
	CompanionUi.button(page, "Down", Vector2(296, 186), Vector2(56, 15), func(): _move_picked(1), 8)
	CompanionUi.button(page, "Remove", Vector2(356, 186), Vector2(58, 15), func(): _remove_picked(), 8)
	CompanionUi.text(page, "Buffs are cast automatically when needed.", Vector2(236, 208), Vector2(200, 12), 7, CompanionUi.DIM)


## What it knows that can go on the bar: its styles, then its spells by spec (A-Z), highest rank first in each (owner
## 2026-10-11); with "Hide lower ranks" only the best rank of each spell (its spellgroup - the client's family of ranks).
func _known(s: CharacterState) -> Array:
	var out := []
	for st in ClassDb.styles_known(s.class_id(), s.specs):
		out.append({"kind": "style", "id": int(st.get("id", 0)), "name": String(st.get("name", "")), "icon": int(st.get("icon", 0))})
	var spells := []
	for line in ClassDb.spell_lines(s.class_id(), s.level, s.specs):
		var spec_name := String(ClassDb.spec(String(line.spec)).get("name", line.spec))
		var levels: Array = line.get("levels", [])
		for k in (line.spells as Array).size():
			var sid := int(line.spells[k])
			var sp := ClassDb.spell(sid)
			var attack := String(sp.get("target", "")).to_lower() in ["enemy", "area", "cone"] or int(sp.get("damage", 0)) > 0
			var group := int(sp.get("spellgroup", 0))
			var family := "%s|%s" % [line.key, str(group) if group != 0 else "%s/%s/%s" % [sp.get("type", ""), sp.get("target", ""), sp.get("damagetype", "")]]
			spells.append({"kind": "spell", "id": sid, "name": String(sp.get("name", "")), "icon": int(sp.get("icon", 0)),
					"attack": attack, "spec": spec_name, "level": int(levels[k]) if k < levels.size() else 0, "family": family,
					"buff": Companions.is_buff(sp)})
	spells.sort_custom(func(a, b):
		if a.spec != b.spec:
			return String(a.spec) < String(b.spec)
		if a.level != b.level:
			return int(a.level) > int(b.level)
		return String(a.name) < String(b.name))
	var seen := {}
	for sp in spells:
		if _hide_lower and seen.has(sp.family):
			continue                                       # (a lower rank of one already listed)
		seen[sp.family] = true
		out.append(sp)
	return out


var _hide_lower := false


func _refresh_tactics(s: CharacterState) -> void:
	var tac: Array = Companions.info(_rec()).get("tactics", [])
	for c in _avail.get_children():
		c.queue_free()
	var last_spec := ""
	for k in _known(s):
		if String(k.kind) == "spell" and String(k.spec) != last_spec:
			last_spec = String(k.spec)                     # a heading per spec
			var h := Label.new()
			h.text = last_spec.to_upper()
			h.add_theme_font_override("font", UiArt.font(true))
			h.add_theme_font_size_override("font_size", 8)
			h.add_theme_color_override("font_color", UiArt.GOLD)
			_avail.add_child(h)
		var on := tac.any(func(t): return String(t.kind) == String(k.kind) and int(t.id) == int(k.id))
		var label := String(k.name) if k.kind == "style" else "%s  (%d)" % [String(k.name), int(k.level)]
		var b := UiArt.button(label, Vector2(196, 14), 8)
		b.disabled = on or tac.size() >= TACTIC_SLOTS
		if bool(k.get("buff", false)):                     # buffs: shown, greyed, cast automatically (owner 2026-10-11)
			b.disabled = true
			b.tooltip_text = "Buffs are automatically cast when needed."
			b.mouse_filter = Control.MOUSE_FILTER_STOP     # (the tooltip shows on a disabled button too)
		var entry: Dictionary = k
		b.pressed.connect(func():
			companions.add_tactic(id, entry)
			refresh())
		_avail.add_child(b)
	for i in TACTIC_SLOTS:
		var b := _bar[i] as Button
		b.text = String(tac[i].get("name", "")).to_upper() if i < tac.size() else "-"
		b.modulate = Color(1.0, 0.85, 0.45) if i == _picked else Color.WHITE


func _bar_clicked(i: int) -> void:
	_picked = i if _picked != i else -1
	refresh()


func _move_picked(d: int) -> void:
	if _picked < 0:
		return
	_picked = companions.move_tactic(id, _picked, d)
	refresh()


func _remove_picked() -> void:
	if _picked < 0:
		return
	companions.remove_tactic(id, _picked)
	_picked = -1
	refresh()


# --- stance -----------------------------------------------------------------------------------------------------

func _build_stance(page: Control) -> void:
	var y := 0.0
	for k in Companions.STANCES:
		var b := UiArt.button(k, Vector2(96, 16), 9)
		b.toggle_mode = true
		b.position = Vector2(14, y)
		var key: String = k
		b.pressed.connect(func():
			companions.set_stance(id, key)
			refresh())
		page.add_child(b)
		_stance_buttons[k] = b
		CompanionUi.text(page, String(STANCE_TEXT[k]), Vector2(118, y), Vector2(SIZE.x - 132, 30), 8, UiArt.CREAM, true)
		y += 40.0
