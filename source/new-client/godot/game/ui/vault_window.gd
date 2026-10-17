class_name VaultWindow
extends ClassicWindow
## The vault (the client's "Bank" window on vault.bmp, 224x400: twenty item rows, each with its slot box down the
## left edge). Opened by right-clicking a vault keeper (old server GameVaultKeeper: the player's vault slots
## FirstVault 110 .. LastVault 149 = 40 slots, so two pages of twenty). Drag items between the vault rows and the
## backpack / sacks; an item dropped on the window goes into the first free vault slot.
## CUSTOM (owner 2026-10-09, "1.65 EXCEPTIONS MADE.txt"): the vault - all 40 slots - is shared by every character of
## the account in the same realm, and keeps coins too (PlayerData._save_vault / _load_vault, vault_deposit / withdraw).

const ROW_H := 18.0
const ROWS := 20
const LIST := Rect2(4, 20, 214, 360)

var page := 0
var first_slot := PlayerData.FIRST_VAULT        # the vault shown: its first slot and size (the server's account vault:
var slot_count := PlayerData.VAULT_SLOTS        # 150, 100 - Server.vault_open)
var _rows: Array = []
var _title: Label
var _page_label: Label


func build() -> void:
	closable = true
	_title = UiArt.label("VAULT", 11, UiArt.GOLD_HI)
	_title.position = Vector2(12, 2)
	_title.size = Vector2(200, 14)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	for i in ROWS:
		var r := VaultRow.new()
		r.window = self
		r.index = i
		r.position = LIST.position + Vector2(0, i * ROW_H)
		r.size = Vector2(LIST.size.x, ROW_H)
		add_child(r)
		_rows.append(r)
	var prev := UiArt.button("<", Vector2(18, 13), 8)
	prev.position = Vector2(60, 384)
	prev.pressed.connect(func(): show_page(page - 1))
	add_child(prev)
	_page_label = UiArt.label("", 8, UiArt.CREAM)
	_page_label.position = Vector2(80, 384)
	_page_label.size = Vector2(64, 13)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_page_label)
	var nxt := UiArt.button(">", Vector2(18, 13), 8)
	nxt.position = Vector2(146, 384)
	nxt.pressed.connect(func(): show_page(page + 1))
	add_child(nxt)
	_build_coins()
	PlayerData.inventory_changed.connect(refresh)
	PlayerData.changed.connect(refresh)


## The vault's coins (CUSTOM, owner 2026-10-09: the 1.65 vault held objects only): a strip under the window with what
## the vault holds and DEPOSIT / WITHDRAW, each asking how much (platinum / gold / silver / copper).
var _coins: Label


func _build_coins() -> void:
	var strip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.06, 0.95)
	sb.border_color = UiArt.GOLD.darkened(0.35)
	sb.set_border_width_all(1)
	strip.add_theme_stylebox_override("panel", sb)
	strip.position = Vector2(4, 402)
	strip.size = Vector2(216, 38)
	add_child(strip)
	_coins = UiArt.label("", 8, UiArt.CREAM)
	_coins.position = Vector2(6, 3)
	_coins.size = Vector2(204, 12)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_child(_coins)
	var dep := UiArt.button("Deposit", Vector2(96, 16), 9)
	dep.position = Vector2(6, 18)
	dep.pressed.connect(func(): _ask_amount(true))
	strip.add_child(dep)
	var wd := UiArt.button("Withdraw", Vector2(96, 16), 9)
	wd.position = Vector2(114, 18)
	wd.pressed.connect(func(): _ask_amount(false))
	strip.add_child(wd)


func _ask_amount(deposit: bool) -> void:
	var have := PlayerData.total_copper() if deposit else PlayerData.vault_copper
	if have <= 0:
		PlayerData.message.emit("You have no coins to deposit." if deposit else "Your vault holds no coins.", "error")
		return
	var d := ConfirmationDialog.new()
	d.title = "DEPOSIT COINS" if deposit else "WITHDRAW COINS"
	d.ok_button_text = "DEPOSIT" if deposit else "WITHDRAW"
	d.cancel_button_text = "CANCEL"
	var box := VBoxContainer.new()
	var info := Label.new()
	info.text = ("You carry %s." if deposit else "Your vault holds %s.") % PlayerData.money_string(have)
	box.add_child(info)
	var row := HBoxContainer.new()
	var fields := {}
	var split := PlayerData.split_money(have)
	for k in ["platinum", "gold", "silver", "copper"]:
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = 999 if k != "platinum" else 999999
		sp.value = int(split.get(k, 0))                  # all of it by default; lower what you don't want to move
		sp.suffix = k.substr(0, 1)
		row.add_child(sp)
		fields[k] = sp
	box.add_child(row)
	d.add_child(box)
	d.confirmed.connect(func():
		var c := int(fields.copper.value) + int(fields.silver.value) * 100 + int(fields.gold.value) * 10000 				+ int(fields.platinum.value) * 10000000
		var ok := PlayerData.vault_deposit(c) if deposit else PlayerData.vault_withdraw(c)
		if not ok and c > 0:
			PlayerData.message.emit("You don't have that much." if deposit else "Your vault doesn't hold that much.", "error")
		d.queue_free())
	d.canceled.connect(d.queue_free)
	get_tree().root.add_child(d)
	d.popup_centered()


## The server's vault (Server.vault_open): which slots - your vault 110-149 or an account vault page 150-249. The coin
## strip is the offline vault's (the server's vaults hold items only).
func open_range(title: String, first: int, count: int) -> void:
	first_slot = first
	slot_count = count
	page = 0
	if _coins:
		_coins.get_parent().visible = false
	open_for(title)


func open_for(keeper: String) -> void:
	_title.text = keeper.to_upper() if keeper != "" else "VAULT"
	show_window()                                         # visible first: refresh() skips a hidden window
	show_page(page)


func show_page(p: int) -> void:
	var pages := maxi(1, ceili(float(slot_count) / ROWS))
	page = clampi(p, 0, pages - 1)
	_page_label.text = "PAGE %d / %d" % [page + 1, pages]
	refresh()


func refresh() -> void:
	if not visible:
		return
	if _coins:
		_coins.text = "VAULT COINS: " + PlayerData.money_string(PlayerData.vault_copper).to_upper()
	for r in _rows:
		(r as VaultRow).refresh()


func slot_of(i: int) -> int:
	return first_slot + page * ROWS + i


func _holds(slot: int) -> bool:
	return slot >= first_slot and slot < first_slot + slot_count


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			show_page(page + 1)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			show_page(page - 1)
			accept_event()
			return
	super._gui_input(event)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return InventorySheet.is_item(data) and not _holds(int(data.slot))


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var to := -1
	for s in range(first_slot, first_slot + slot_count):
		if not PlayerData.inventory.has(s):
			to = s
			break
	if to < 0:
		PlayerData.message.emit("Your vault is full.", "error")
		return
	PlayerData.move(int(data.slot), to)


class VaultRow extends Control:
	var window: VaultWindow
	var index := 0
	var _icon: TextureRect
	var _name: Label
	var _hi: ColorRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_hi = ColorRect.new()
		_hi.color = Color(1.0, 0.8, 0.35, 0.18)
		_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hi.visible = false
		add_child(_hi)
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.position = Vector2(2, 0)
		_icon.size = Vector2(16, 16)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_name = UiArt.label("", 8, UiArt.CREAM)
		_name.position = Vector2(24, 1)
		_name.size = Vector2(186, 14)
		_name.clip_text = true
		add_child(_name)

	func slot() -> int:
		return window.slot_of(index)

	func refresh() -> void:
		_hi.size = size
		var e := PlayerData.entry(slot())
		var it := ItemDb.item(String(e.id)) if not e.is_empty() else {}
		_icon.texture = ItemDb.icon(int(it.get("icon", 0))) if not it.is_empty() else null
		var n := String(it.get("name", "")).to_upper()
		if not e.is_empty() and int(e.get("count", 1)) > 1:
			n += " (%d)" % int(e.count)
		_name.text = n
		_hi.visible = PlayerData.selected_slot == slot() and not e.is_empty()
		tooltip_text = String(it.get("name", "")).to_upper()

	func _get_drag_data(_p: Vector2) -> Variant:
		return InventorySheet.drag_data(slot(), self)

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		var ok := InventorySheet.is_item(data)
		_hi.size = size
		_hi.visible = ok and int(data.slot) != slot()
		return ok

	func _drop_data(_p: Vector2, data: Variant) -> void:
		if int(data.slot) == slot():                        # put back where it was (a double-click: to the backpack)
			if InventorySheet.double_clicked():
				var to := PlayerData.first_free()
				if to >= 0:
					PlayerData.move(slot(), to)
			return
		PlayerData.move(int(data.slot), slot())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			refresh()

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
				var to := PlayerData.first_free()                # double-click: back into the backpack
				if to >= 0:
					PlayerData.move(slot(), to)
				accept_event()
