class_name MerchantWindow
extends ClassicWindow
## The merchant (shop) window on the client's merchant.bmp (350x448: item list area, scroll track, five price boxes
## with the mithril / platinum / gold / silver / copper coins). Opened by right-clicking a merchant (period: "when I
## right clicked on Reeni, she just looked friendly and opened her merchant window").
## Stock: content/items/merchants.json (the old server's merchant lists - not proven 1.65, ledger). Click an item to
## see its price; BUY (or double-click) buys it into the first free backpack slot. Sell: drag an item from the
## backpack onto the window - the merchant pays 50% of its value (old server item_sell_ratio 50).
## Chat lines are the old server's: "You just bought {item} for {price}.", "{merchant} gives you {price} for {item}."

const ROW_H := 18.0
const ROWS := 20
const LIST := Rect2(8, 20, 324, 360)
const COIN_BOX_X := [64, 109, 154, 199, 244]        # price boxes (original px)
const COIN_BOX_Y := 393.0                    # inside the 13 px box (rows 392-404)

var npc_name := ""
var list_id := ""
var page := 0
var pages: Array = []                              # [[item id, ...] per page]
var selected := ""
var _rows: Array = []
var _title: Label
var _page_label: Label
var _coins: Array = []
var _buy: Button


func build() -> void:
	closable = true
	_title = UiArt.label("", 11, UiArt.GOLD_HI)
	_title.position = Vector2(16, 2)
	_title.size = Vector2(318, 14)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	for i in ROWS:
		var r := ShopRow.new()
		r.window = self
		r.position = LIST.position + Vector2(0, i * ROW_H)
		r.size = Vector2(LIST.size.x, ROW_H)
		add_child(r)
		_rows.append(r)
	for i in 5:
		# the art's price boxes are holes (transparent, 33 x 13 at y 392): the game world showed through behind the
		# digits and no price could be read (owner 2026-10-11) - a dark field fills each, the digits on it
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.02, 0.02)
		bg.position = Vector2(COIN_BOX_X[i], 392)
		bg.size = Vector2(33, 13)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		var l := UiArt.label("", 8, UiArt.CREAM)
		l.position = Vector2(COIN_BOX_X[i], COIN_BOX_Y)
		l.size = Vector2(33, 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
		_coins.append(l)
	var prev := UiArt.button("<", Vector2(22, 16), 9)
	prev.position = Vector2(10, 426)
	prev.pressed.connect(func(): show_page(page - 1))
	add_child(prev)
	_page_label = UiArt.label("", 8, UiArt.CREAM)
	_page_label.position = Vector2(34, 428)
	_page_label.size = Vector2(60, 12)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_page_label)
	var nxt := UiArt.button(">", Vector2(22, 16), 9)
	nxt.position = Vector2(96, 426)
	nxt.pressed.connect(func(): show_page(page + 1))
	add_child(nxt)
	_buy = UiArt.button("BUY", Vector2(80, 18), 10)
	_buy.position = Vector2(250, 424)
	_buy.pressed.connect(buy_selected)
	add_child(_buy)


## Where the shop opens: at the top, centred (owner 2026-10-14: not in the top right corner), the whole window on the
## screen.
func _place_top_center() -> void:
	var area := get_parent_area_size()
	position = Vector2(clampf(floorf((area.x - size.x) * 0.5), 0.0, maxf(0.0, area.x - size.x)), 4.0)


func open_for(merchant: String, items_list: String) -> void:
	if not visible:
		_place_top_center()
	npc_name = merchant
	list_id = items_list
	_title.text = merchant.to_upper()
	pages = []
	for e in ItemDb.merchant_list(items_list):
		var p := int(e[0])
		while pages.size() <= p:
			pages.append([])
		pages[p].append(String(e[2]))
	pages = pages.filter(func(p): return not (p as Array).is_empty())
	selected = ""
	show_page(0)
	show_window()


## The server's merchant (Offline DAoC Rebuilt): its pages as the MerchantWindow packets brought them - each item a
## runtime ItemDb entry "srvm:<page>:<index>" (its slot on the server is page * 30 + index).
var server_window := -1


func open_server(merchant: String, server_pages: Dictionary, window_type: int) -> void:
	npc_name = merchant
	list_id = ""
	server_window = window_type
	_title.text = merchant.to_upper()
	pages = []
	var keys := server_pages.keys()
	keys.sort()
	for k in keys:
		pages.append(server_pages[k])
	if not visible:
		selected = ""
		page = 0
		_place_top_center()
	show_page(page)
	show_window()


func show_page(p: int) -> void:
	page = clampi(p, 0, maxi(pages.size() - 1, 0))
	var items: Array = pages[page] if page < pages.size() else []
	for i in ROWS:
		_rows[i].set_item(String(items[i]) if i < items.size() else "")
	_page_label.text = "PAGE %d / %d" % [page + 1, maxi(pages.size(), 1)]
	_show_price()


func select_item(id: String) -> void:
	selected = id
	for r in _rows:
		r.queue_redraw()
	_show_price()


func _show_price() -> void:
	var price := int(ItemDb.item(selected).get("price", 0)) if selected != "" else 0
	var parts := PlayerData.split_money(price)
	var keys := ["mithril", "platinum", "gold", "silver", "copper"]
	for i in 5:
		_coins[i].text = str(parts[keys[i]]) if selected != "" else ""
	_buy.disabled = selected == ""


func buy_selected() -> void:
	if selected == "":
		return
	if Server.active and selected.begins_with("srvm:"):   # the server's merchant: PlayerBuyRequest (page * 30 + index)
		var parts := selected.split(":")
		var v: Node = Server.viewer()
		if v:
			var r: Vector3 = Server.to_region(Server.current_zone_id(), v.player.global_position)
			Server.client.call("BuyItem", int(r.x), int(r.y), int(parts[1]) * 30 + int(parts[2]), 1, maxi(server_window, 0))
		return
	PlayerData.buy(selected, npc_name)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return InventorySheet.is_item(data) and PlayerData.is_backpack(int(data.slot))


func _drop_data(_pos: Vector2, data: Variant) -> void:
	PlayerData.sell(int(data.slot), npc_name)


class ShopRow extends Control:
	var window: MerchantWindow
	var item_id := ""
	var _icon: TextureRect
	var _name: Label
	var _level: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.position = Vector2(2, 1)
		_icon.size = Vector2(16, 16)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_name = UiArt.label("", 8, UiArt.CREAM)
		_name.position = Vector2(22, 2)
		_name.size = Vector2(250, 14)
		_name.clip_text = true
		add_child(_name)
		_level = UiArt.label("", 8, UiArt.DIM)
		_level.position = Vector2(274, 2)
		_level.size = Vector2(46, 14)
		_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_level)

	func set_item(id: String) -> void:
		item_id = id
		var it := ItemDb.item(id) if id != "" else {}
		_icon.texture = ItemDb.icon(int(it.get("icon", 0))) if not it.is_empty() else null
		_name.text = String(it.get("name", "")).to_upper()
		var lvl := int(it.get("level", 0))
		_level.text = ("LVL %d" % lvl) if not it.is_empty() and lvl > 0 else ""
		tooltip_text = String(it.get("name", "")).to_upper()
		queue_redraw()

	func _draw() -> void:
		if item_id != "" and window and window.selected == item_id:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.8, 0.35, 0.18))

	func _make_custom_tooltip(_for_text: String) -> Object:          # weapons / armour: the mini delve box
		return ItemTooltip.make(ItemDb.item(item_id)) if item_id != "" else null

	func _gui_input(event: InputEvent) -> void:
		if item_id == "" or not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			window.select_item(item_id)
			if event.double_click:
				window.buy_selected()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			window.select_item(item_id)                    # its standard information; then Shift+I = delve
			PlayerData.delve_id = item_id
			PlayerData.selected_slot = -1
			PlayerData.summary.emit(ItemDb.item(item_id))
			accept_event()
