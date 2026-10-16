class_name ExchangeWindow
extends ClassicWindow
## The Realm Exchange (the CLAUDE VERSION server's RealmExchangeBroker - Server's exchange section) in the black
## granite of the client's windows (owner 2026-10-13: "Browse the exchange doesn't bring up a market interface. It
## needs to be built for the games new old black granite UI art style"). The 1.65 client had no market window: the
## frame is the chat box granite (chatext) the other later-client pieces use, with the bar buttons, the client's
## fonts and its item icons. Two pages:
##   BROWSE - the server's market search with its own filters (name, slot, armour, damage, level, quality, price, a
##            bonus, crafted only), 20 results a page with their prices; BUY (or double-click, or drag a result into
##            the backpack - the server's way).
##   MY LISTINGS - your listing chest (100 slots a chest page, five pages of twenty here): drag a backpack item in
##            to list it (its price is asked), SET PRICE to change it, TAKE BACK (or drag it to the backpack) cancels.
## SALE PROCEEDS: what the broker holds for you (its greeting's amount, sales while you are online added) and CLAIM.
## The broker answers only within reach and in its own realm (the server's rules); its words come in the chat.
## Text sizes (owner 2026-10-13: "some of the text is small and hard to read"): rows 11, captions 10, nothing under 10.

const SIZE := Vector2(700, 556)
const ROW_H := 20.0
const ROWS := 20
const LIST_X := 222.0
const LIST_Y := 92.0
const COL_X := 18.0                                 # the filter / help column
const COL_W := 186.0
const TEXT := 11                                    # row text
const CAPTION := 10                                 # captions, headers, notes
const SLOTS := [["ANY SLOT", 0], ["HEAD", 1], ["TORSO", 5], ["ARMS", 8], ["HANDS", 2], ["LEGS", 7], ["FEET", 3],
		["CLOAK", 6], ["NECK", 9], ["JEWEL", 4], ["WAIST", 12], ["WRIST", 13], ["RING", 15], ["ONE HANDED", 100],
		["LEFT HAND", 101], ["TWO HANDED", 102], ["RANGED", 103], ["INSTRUMENT", 104], ["SHIELD", 105],
		["OTHER ITEMS", 106]]
const ARMORS := ["ANY ARMOR", "CLOTH", "LEATHER", "STUDDED", "CHAIN", "PLATE", "REINFORCED", "SCALE"]
const DAMAGES := ["ANY DAMAGE", "CRUSH", "SLASH", "THRUST"]
const BONUSES := [["ANY BONUS", 0], ["STAT", 1], ["RESIST", 5], ["HIT POINTS", 4], ["POWER", 3]]
# the server's stat codes (MarketSearch.CheckForBonus; its 0, strength, is never matched there - not offered)
const STATS := [["CONSTITUTION", 1], ["DEXTERITY", 2], ["QUICKNESS", 3], ["PIETY", 4], ["EMPATHY", 5],
		["INTELLIGENCE", 6], ["CHARISMA", 7], ["ANY ACUITY", 8]]
const RESISTS := ["BODY", "COLD", "HEAT", "ENERGY", "MATTER", "SPIRIT", "THRUST", "CRUSH", "SLASH"]
# the list's columns: x, width (row units)
const C_NAME := [28.0, 236.0]
const C_LEVEL := [268.0, 34.0]
const C_QUALITY := [306.0, 40.0]
const C_PRICE := [350.0, 104.0]

var tab := "browse"
var selected := -1                                 # browse: the result's place; listings: the chest slot
var _lpage := 0                                    # the listing chest's twenty shown (0-4)
var _ask_price := -1                               # a chest slot just filled: its price is asked once it arrives
var _rows: Array = []
var _browse: Control
var _listings: Control
var _tab_browse: Button
var _tab_listings: Button
var _proceeds: Label
var _claim: Button
var _status: Label
var _page_label: Label
var _action: Button
var _action2: Button
var _header_price: Label
# the filters
var _name: LineEdit
var _slot: OptionButton
var _armor: OptionButton
var _damage: OptionButton
var _level_min: LineEdit
var _level_max: LineEdit
var _quality: LineEdit
var _price_max: LineEdit
var _crafted: Button
var _bonus: OptionButton
var _bonus_pick: OptionButton
var _bonus_amount: LineEdit
var _chest_label: Label


func build() -> void:
	closable = false                                       # (the granite has no cross: its own X button)
	var title := UiArt.label("REALM EXCHANGE", 13, UiArt.GOLD_HI)
	title.position = Vector2(0, 6)
	title.size = Vector2(SIZE.x, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var x := UiArt.button("X", Vector2(24, 20), 10)
	x.position = Vector2(SIZE.x - 34, 6)
	x.pressed.connect(hide_window)
	add_child(x)
	_tab_browse = _tab_button("BROWSE", Vector2(14, 32), "browse")
	_tab_listings = _tab_button("MY LISTINGS", Vector2(142, 32), "listings")
	_proceeds = UiArt.label("", TEXT, UiArt.CREAM)
	_proceeds.position = Vector2(270, 32)
	_proceeds.size = Vector2(SIZE.x - 270 - 108, 22)
	_proceeds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_proceeds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_proceeds.clip_text = true
	add_child(_proceeds)
	_claim = UiArt.button("CLAIM", Vector2(88, 22), 10)
	_claim.position = Vector2(SIZE.x - 102, 32)
	_claim.pressed.connect(func(): Server.command("/whisper claim sale proceeds"))
	add_child(_claim)
	_build_list()
	_build_browse()
	_build_listings()
	Server.exchange_changed.connect(refresh)
	Server.exchange_open.connect(open_tab)
	PlayerData.inventory_changed.connect(refresh)


func _tab_button(text: String, at: Vector2, which: String) -> Button:
	var b := UiArt.button(text, Vector2(122, 22), 10)
	b.position = at
	b.toggle_mode = true
	b.pressed.connect(func(): show_tab(which))
	add_child(b)
	return b


## The results / listings list on the right, its header and the controls under it (shared by both pages).
func _build_list() -> void:
	add_child(_panel(Rect2(LIST_X - 4, LIST_Y - 26, SIZE.x - LIST_X - 6, ROWS * ROW_H + 32)))
	var cols := [["ITEM", C_NAME, HORIZONTAL_ALIGNMENT_LEFT], ["LVL", C_LEVEL, HORIZONTAL_ALIGNMENT_RIGHT],
			["QUA", C_QUALITY, HORIZONTAL_ALIGNMENT_RIGHT], ["PRICE", C_PRICE, HORIZONTAL_ALIGNMENT_RIGHT]]
	for c in cols:
		var h := UiArt.label(String(c[0]), CAPTION, UiArt.GOLD)
		h.position = Vector2(LIST_X + float(c[1][0]), LIST_Y - 21)
		h.size = Vector2(float(c[1][1]), 14)
		h.horizontal_alignment = c[2]
		add_child(h)
		if String(c[0]) == "PRICE":
			_header_price = h
	for i in ROWS:
		var r := ExRow.new()
		r.window = self
		r.index = i
		r.position = Vector2(LIST_X, LIST_Y + i * ROW_H)
		r.size = Vector2(SIZE.x - LIST_X - 18, ROW_H)
		add_child(r)
		_rows.append(r)
	var y := LIST_Y + ROWS * ROW_H + 14
	var prev := UiArt.button("<", Vector2(28, 22), 10)
	prev.position = Vector2(LIST_X, y)
	prev.pressed.connect(func(): _page_step(-1))
	add_child(prev)
	_page_label = UiArt.label("", TEXT, UiArt.CREAM)
	_page_label.position = Vector2(LIST_X + 30, y + 3)
	_page_label.size = Vector2(110, 16)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_page_label)
	var nxt := UiArt.button(">", Vector2(28, 22), 10)
	nxt.position = Vector2(LIST_X + 142, y)
	nxt.pressed.connect(func(): _page_step(1))
	add_child(nxt)
	_action2 = UiArt.button("", Vector2(108, 22), 10)
	_action2.position = Vector2(SIZE.x - 240, y)
	_action2.pressed.connect(_do_action2)
	add_child(_action2)
	_action = UiArt.button("", Vector2(108, 22), 10)
	_action.position = Vector2(SIZE.x - 126, y)
	_action.pressed.connect(_do_action)
	add_child(_action)
	_status = UiArt.label("", CAPTION, UiArt.DIM)
	_status.position = Vector2(COL_X, SIZE.y - 24)
	_status.size = Vector2(SIZE.x - COL_X * 2, 14)
	_status.clip_text = true
	add_child(_status)


func _build_browse() -> void:
	_browse = Control.new()
	_browse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_browse)
	_browse.add_child(_panel(Rect2(COL_X - 8, LIST_Y - 26, COL_W + 16, ROWS * ROW_H + 32)))
	var y := LIST_Y - 22
	_name = _text_field("ANY NAME")
	_name.max_length = 63
	_name.text_submitted.connect(func(_t): _name.release_focus(); search())
	y = _put(_browse, "NAME", _name, y)
	_slot = _choice(SLOTS.map(func(e): return e[0]))
	y = _put(_browse, "SLOT", _slot, y)
	_armor = _choice(ARMORS)
	y = _put(_browse, "ARMOR", _armor, y)
	_damage = _choice(DAMAGES)
	y = _put(_browse, "DAMAGE", _damage, y)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	_level_min = _number("1", 2, 78)
	_level_max = _number("51", 2, 78)
	lv.add_child(_level_min)
	var to := UiArt.label("TO", CAPTION, UiArt.DIM)
	to.custom_minimum_size = Vector2(14, 20)
	to.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.add_child(to)
	lv.add_child(_level_max)
	y = _put(_browse, "LEVEL", lv, y)
	_quality = _number("ANY", 3, COL_W)
	y = _put(_browse, "MINIMUM QUALITY %", _quality, y)
	_price_max = _number("ANY", 6, COL_W)
	y = _put(_browse, "MAXIMUM PRICE IN GOLD", _price_max, y)
	_bonus = _choice(BONUSES.map(func(e): return e[0]))
	_bonus.item_selected.connect(func(_i): _bonus_changed())
	y = _put(_browse, "BONUS", _bonus, y)
	_bonus_pick = _choice([])
	_bonus_amount = _number("AT LEAST ...", 3, COL_W)
	for c in [_bonus_pick, _bonus_amount]:
		(c as Control).position = Vector2(COL_X, y)
		_fix_size(c, Vector2(COL_W, 20))
		_browse.add_child(c)
	y += 28.0
	_crafted = UiArt.button("PLAYER CRAFTED ONLY", Vector2(COL_W, 22), 9)
	_crafted.toggle_mode = true
	_crafted.position = Vector2(COL_X, y)
	_browse.add_child(_crafted)
	var go := UiArt.button("SEARCH", Vector2(90, 24), 11)
	go.position = Vector2(COL_X, LIST_Y + ROWS * ROW_H - 28)
	go.pressed.connect(search)
	_browse.add_child(go)
	var clear := UiArt.button("CLEAR", Vector2(90, 24), 11)
	clear.position = Vector2(COL_X + COL_W - 90, LIST_Y + ROWS * ROW_H - 28)
	clear.pressed.connect(_clear_filters)
	_browse.add_child(clear)
	_bonus_changed()


func _build_listings() -> void:
	_listings = Control.new()
	_listings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_listings)
	_listings.add_child(_panel(Rect2(COL_X - 8, LIST_Y - 26, COL_W + 16, ROWS * ROW_H + 32)))
	var help := UiArt.label("TO SELL: DRAG AN ITEM FROM YOUR BACKPACK ONTO THE LIST, THEN SET ITS PRICE.\n\n" +
			"SET PRICE CHANGES A PRICE. A PRICE OF 0 KEEPS THE ITEM HERE, NOT FOR SALE.\n\n" +
			"TO CANCEL: TAKE BACK, OR DRAG THE LISTING TO YOUR BACKPACK.\n\n" +
			"MONEY FROM SALES WAITS HERE: CLAIM IT AT THE TOP.\n\nYOUR LISTINGS NEVER EXPIRE.", CAPTION, UiArt.CREAM, false)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.position = Vector2(COL_X, LIST_Y - 20)
	_fix_size(help, Vector2(COL_W, 290))
	_listings.add_child(help)
	_chest_label = UiArt.label("", TEXT, UiArt.GOLD_HI)
	_chest_label.position = Vector2(COL_X, LIST_Y + 284)
	_chest_label.size = Vector2(COL_W, 16)
	_chest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_listings.add_child(_chest_label)
	var prev := UiArt.button("< CHEST", Vector2(90, 22), 10)
	prev.position = Vector2(COL_X, LIST_Y + 304)
	prev.pressed.connect(func(): Server.command("/whisper previous listing page"))
	_listings.add_child(prev)
	var nxt := UiArt.button("CHEST >", Vector2(90, 22), 10)
	nxt.position = Vector2(COL_X + COL_W - 90, LIST_Y + 304)
	nxt.pressed.connect(func(): Server.command("/whisper next listing page"))
	_listings.add_child(nxt)
	var how := UiArt.button("HOW IT WORKS", Vector2(COL_W, 24), 10)
	how.position = Vector2(COL_X, LIST_Y + ROWS * ROW_H - 28)
	how.pressed.connect(func(): Server.command("/whisper how does this work"))
	_listings.add_child(how)


## A caption over a control in the filter column; returns the next row's y.
func _put(parent: Control, caption: String, c: Control, y: float) -> float:
	var l := UiArt.label(caption, CAPTION, UiArt.GOLD)
	l.position = Vector2(COL_X, y)
	l.size = Vector2(COL_W, 14)
	parent.add_child(l)
	c.position = Vector2(COL_X, y + 15)
	if not (c is HBoxContainer):
		_fix_size(c, Vector2(COL_W, 20))
	parent.add_child(c)
	return y + 42.0


## A label's size once it is in the tree (outside it Godot measures text in its default font and keeps that size -
## UiArt.themed): wrapped text then stays inside its box.
static func _fix_size(l: Control, s: Vector2) -> void:
	l.custom_minimum_size = Vector2(s.x, 0 if l is Label else s.y)
	l.size = s
	l.ready.connect(func(): l.size = s)


# ---------------------------------------------------------------- opening, pages

## The broker opened a page (its [Browse the exchange] / [Manage my listings]).
func open_tab(which: String) -> void:
	show_tab(which)
	show_window()
	refresh()
	if which == "browse" and Server.market_items.is_empty():
		search()                                          # everything for sale, first page


func show_tab(which: String) -> void:
	tab = which
	selected = -1
	_tab_browse.set_pressed_no_signal(which == "browse")
	_tab_listings.set_pressed_no_signal(which == "listings")
	_browse.visible = which == "browse"
	_listings.visible = which == "listings"
	_header_price.text = "PRICE" if which == "browse" else "YOUR PRICE"
	_action.text = "BUY" if which == "browse" else "SET PRICE"
	_action2.text = "INFO" if which == "browse" else "TAKE BACK"
	refresh()


func _page_step(d: int) -> void:
	if tab == "browse":
		var p := clampi(Server.market_page + d, 0, Server.market_pages)
		if p != Server.market_page:
			Server.exchange_search(Server.market_search, p)
	else:
		_lpage = clampi(_lpage + d, 0, 4)
		selected = -1
		refresh()


func refresh() -> void:
	if not visible or _rows.is_empty():
		return
	var p := Server.proceeds
	_proceeds.text = "SALE PROCEEDS: " + ("ASK THE BROKER" if p < 0 else ("NONE WAITING" if p == 0 else
			PlayerData.money_string(p).to_upper()))
	_proceeds.add_theme_color_override("font_color", UiArt.GOLD_HI if p > 0 else UiArt.CREAM)
	_proceeds.tooltip_text = _proceeds.text
	_claim.disabled = p == 0
	for r in _rows:
		(r as ExRow).refresh()
	if tab == "browse":
		_page_label.text = "PAGE %d / %d" % [Server.market_page + 1, Server.market_pages + 1]
		var n := Server.market_count
		_status.text = ("%d LISTINGS FOUND" % n) if n >= 0 else ("SEARCHING..." if Server.market_items.is_empty() else "")
		if n > 20 * 256:
			_status.text += " - NARROW THE SEARCH TO SEE THEM ALL"
		_action.disabled = selected < 0 or selected >= Server.market_items.size()
		_action2.disabled = _action.disabled
	else:
		_page_label.text = "SLOTS %d-%d" % [_lpage * ROWS + 1, _lpage * ROWS + ROWS]
		_chest_label.text = "CHEST PAGE %d" % (Server.listing_page + 1)
		_status.text = "%d ITEMS LISTED ON THIS CHEST PAGE" % Server.listings.size()
		_action.disabled = not Server.listings.has(selected)
		_action2.disabled = _action.disabled
	if _ask_price >= 0 and Server.listings.has(_ask_price):
		var s := _ask_price
		_ask_price = -1
		ask_price(s)


## The id shown on row i: a result's or a listing's runtime ItemDb id ("" empty).
func id_at(i: int) -> String:
	if tab == "browse":
		return String(Server.market_items[i]) if i < Server.market_items.size() else ""
	return String(Server.listings.get(chest_slot(i), ""))


func chest_slot(i: int) -> int:
	return Server.CHEST_FIRST + _lpage * ROWS + i


## Row i's key: the result's place (browse) or its chest slot (listings).
func key_at(i: int) -> int:
	return i if tab == "browse" else chest_slot(i)


func select_row(i: int) -> void:
	selected = key_at(i)
	refresh()


# ---------------------------------------------------------------- the search

func search() -> void:
	var lmax := _value(_level_max, 51)
	var f := {"name": _name.text.strip_edges(), "slot": int(SLOTS[_slot.selected][1]), "armor": _armor.selected,
			"damage": _damage.selected, "level_min": clampi(_value(_level_min, 1), 1, 51),
			"level_max": 52 if lmax >= 51 else maxi(lmax, 1),   # 52: no top (the server's)
			"quality_min": clampi(_value(_quality, 0), 0, 100), "price_max": _value(_price_max, 0) * 10000,
			"crafted": 1 if _crafted.button_pressed else 0}
	var b := int(BONUSES[_bonus.selected][1])
	if b > 0:
		f["bonus1"] = b
		match b:
			1: f["bonus1_value"] = int(STATS[_bonus_pick.selected][1])
			5: f["bonus1_value"] = _bonus_pick.selected
			_: f["bonus1_value"] = maxi(_value(_bonus_amount, 1), 1)
	selected = -1
	Server.market_items = []
	Server.exchange_search(f, 0)
	refresh()


func _clear_filters() -> void:
	for le in [_name, _level_min, _level_max, _quality, _price_max, _bonus_amount]:
		(le as LineEdit).text = ""
	for o in [_slot, _armor, _damage, _bonus]:
		(o as OptionButton).select(0)
	_crafted.set_pressed_no_signal(false)
	_bonus_changed()


func _bonus_changed() -> void:
	var b := int(BONUSES[_bonus.selected][1])
	_bonus_pick.clear()
	if b == 1:
		for s in STATS:
			_bonus_pick.add_item(String(s[0]))
	elif b == 5:
		for r in RESISTS:
			_bonus_pick.add_item(r)
	_bonus_pick.visible = b == 1 or b == 5
	_bonus_amount.visible = b == 3 or b == 4


# ---------------------------------------------------------------- buying, listing

func _do_action() -> void:
	if tab == "browse":
		buy(selected)
	elif Server.listings.has(selected):
		ask_price(selected)


func _do_action2() -> void:
	if tab == "browse":
		if selected >= 0:
			Server.detail_shown(10, selected)
	elif Server.listings.has(selected):
		var to := PlayerData.first_free()
		if to < 0:
			PlayerData.message.emit("You need an empty backpack slot.", "error")
		else:
			PlayerData.move(selected, to)


## A result bought after a yes (BUY / double-click; dragging it into the backpack buys at once, as the server has it).
func buy(place: int) -> void:
	if place < 0 or place >= Server.market_items.size():
		return
	var it := ItemDb.item(String(Server.market_items[place]))
	var price := int(it.get("price", 0))
	var text := "BUY %s FOR %s?" % [String(it.get("name", "")), PlayerData.money_string(price)]
	if price > PlayerData.total_copper():
		text = "%s COSTS %s - MORE THAN YOU CARRY." % [String(it.get("name", "")), PlayerData.money_string(price)]
	UiArt.confirm(get_parent(), "REALM EXCHANGE", text, "BUY", "CANCEL", func(): Server.exchange_buy(place))


## A backpack item dropped on the listing chest: moved into `slot` (or the first free one); its price asked next.
func list_item(from: int, slot := -1) -> void:
	if slot < 0 or Server.listings.has(slot):
		slot = -1
		for i in 100:
			var s := Server.CHEST_FIRST + i
			if not Server.listings.has(s):
				slot = s
				break
	if slot < 0:
		PlayerData.message.emit("This chest page is full - use CHEST > for the next.", "error")
		return
	if PlayerData.move(from, slot):
		_ask_price = slot


## The price box in the granite: platinum / gold / silver / copper (0 = kept in the chest, not for sale).
func ask_price(slot: int) -> void:
	var it := ItemDb.item(String(Server.listings.get(slot, "")))
	if it.is_empty():
		return
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	get_parent().add_child(shade)
	var box := Control.new()
	box.size = Vector2(420, 168)
	box.position = ((get_parent().size - box.size) * 0.5).floor()
	shade.add_child(box)
	box.add_child(_granite(box.size))
	var t := UiArt.label("SET A PRICE", 12, UiArt.GOLD_HI)
	t.position = Vector2(0, 16)
	t.size = Vector2(box.size.x, 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var nm := UiArt.label(String(it.get("name", "")), TEXT, UiArt.CREAM)
	nm.position = Vector2(16, 36)
	nm.size = Vector2(box.size.x - 32, 16)
	nm.clip_text = true
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var have := maxi(Server.listing_price(slot), 0)
	var parts := PlayerData.split_money(have)
	var fields := {}
	var x := 22.0
	for k in [["platinum", "PLAT"], ["gold", "GOLD"], ["silver", "SILVER"], ["copper", "COPPER"]]:
		var f := _number("0", 3, 50)
		f.text = str(int(parts[k[0]])) if int(parts[k[0]]) > 0 else ""
		f.position = Vector2(x, 62)
		_fix_size(f, Vector2(50, 22))
		box.add_child(f)
		var l := UiArt.label(String(k[1]), CAPTION, UiArt.GOLD)
		l.position = Vector2(x + 53, 66)
		l.size = Vector2(44, 14)
		box.add_child(l)
		fields[k[0]] = f
		x += 96.0
	var note := UiArt.label("A PRICE OF 0 KEEPS IT IN THE CHEST, NOT FOR SALE", CAPTION, UiArt.DIM)
	note.position = Vector2(0, 94)
	note.size = Vector2(box.size.x, 14)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	var done := func(ok: bool):
		if ok:
			var c := _value(fields.copper, 0) + _value(fields.silver, 0) * 100 + _value(fields.gold, 0) * 10000 \
					+ _value(fields.platinum, 0) * 10000000
			Server.set_listing_price(slot, c)
		shade.queue_free()
	var yes := UiArt.button("LIST IT", Vector2(110, 24), 11)
	yes.position = Vector2(box.size.x * 0.5 - 120, 120)
	yes.pressed.connect(done.bind(true))
	box.add_child(yes)
	var no := UiArt.button("CANCEL", Vector2(110, 24), 11)
	no.position = Vector2(box.size.x * 0.5 + 10, 120)
	no.pressed.connect(done.bind(false))
	box.add_child(no)
	for k in fields:                                       # Enter in any box lists it
		(fields[k] as LineEdit).text_submitted.connect(func(_t): done.call(true))


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_page_step(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			accept_event()
			return
	super._gui_input(event)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return tab == "listings" and InventorySheet.is_item(data) and PlayerData.is_backpack(int(data.slot))


func _drop_data(_pos: Vector2, data: Variant) -> void:
	list_item(int(data.slot))


# ---------------------------------------------------------------- the granite pieces

## The chat box granite (chatext) as a nine-patch of `s` layout units (UiArt.confirm's box).
static func _granite(s: Vector2) -> Control:
	var holder := Control.new()
	holder.scale = Vector2(0.25, 0.25)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var np := NinePatchRect.new()
	np.texture = UiArt.tex("chatext")
	np.region_rect = Rect2(0, 64 * UiArt.K, 512 * UiArt.K, 64 * UiArt.K)
	for side in [[SIDE_LEFT, 3], [SIDE_TOP, 12], [SIDE_RIGHT, 12], [SIDE_BOTTOM, 3]]:
		np.set_patch_margin(side[0], int(side[1] * UiArt.K))
	np.size = s * 4.0
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(np)
	return holder


## A dark inset field inside the granite (the vault's coin strip look).
static func _panel(r: Rect2) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.02, 0.55)
	sb.border_color = UiArt.GOLD.darkened(0.45)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A text box in the granite: black field, thin gold rim, cream caps text (Esc lets go of it).
static func _text_field(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.add_theme_font_override("font", UiArt.font(true))
	le.add_theme_font_size_override("font_size", TEXT)
	le.add_theme_color_override("font_color", UiArt.CREAM)
	le.add_theme_color_override("font_placeholder_color", UiArt.DIM)
	le.add_theme_color_override("caret_color", UiArt.GOLD_HI)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.75)
	box.border_color = UiArt.GOLD.darkened(0.4)
	box.set_border_width_all(1)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	le.add_theme_stylebox_override("normal", box)
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = UiArt.GOLD_HI
	le.add_theme_stylebox_override("focus", focus)
	le.placeholder_text = placeholder
	le.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			le.release_focus()
			le.accept_event())
	UiArt.themed(le)
	return le


## A whole-number box (digits only; empty = its placeholder's meaning).
static func _number(placeholder: String, digits: int, w: float) -> LineEdit:
	var le := _text_field(placeholder)
	le.max_length = digits
	_fix_size(le, Vector2(w, 20))
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.text_changed.connect(func(t: String):
		var d := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				d += ch
		if d != t:
			le.text = d
			le.caret_column = d.length())
	le.text_submitted.connect(func(_t): le.release_focus())
	return le


static func _value(le: LineEdit, empty: int) -> int:
	return int(le.text) if le.text.strip_edges() != "" else empty


static func _choice(items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(COL_W, 20)
	o.focus_mode = Control.FOCUS_NONE
	o.clip_text = true
	o.fit_to_longest_item = false
	o.add_theme_font_override("font", UiArt.font(true))
	o.add_theme_font_size_override("font_size", TEXT)
	o.add_theme_color_override("font_color", UiArt.CREAM)
	o.add_theme_color_override("font_hover_color", UiArt.GOLD_HI)
	o.add_theme_stylebox_override("normal", UiArt.bar_style(0))
	o.add_theme_stylebox_override("hover", UiArt.bar_style(1))
	o.add_theme_stylebox_override("pressed", UiArt.bar_style(2))
	o.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for it in items:
		o.add_item(String(it).to_upper())
	if items.size() > 0:
		o.select(0)
	UiArt.themed(o)
	var pop := o.get_popup()
	pop.add_theme_font_override("font", UiArt.font(true))
	pop.add_theme_font_size_override("font_size", 16)
	pop.add_theme_color_override("font_color", UiArt.CREAM)
	pop.add_theme_color_override("font_hover_color", UiArt.GOLD_HI)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.065, 0.06, 0.97)
	panel.border_color = UiArt.GOLD.darkened(0.3)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(4)
	pop.add_theme_stylebox_override("panel", panel)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(0.3, 0.22, 0.1, 0.9)
	pop.add_theme_stylebox_override("hover", hov)
	return o


## "12G 50S" - a price short enough for its column (the whole sum in the hover / the buy question).
static func money_short(c: int) -> String:
	if c <= 0:
		return "-"
	var p := PlayerData.split_money(c)
	var parts := []
	for k in [["mithril", "M"], ["platinum", "P"], ["gold", "G"], ["silver", "S"], ["copper", "C"]]:
		if int(p[k[0]]) > 0:
			parts.append("%d%s" % [int(p[k[0]]), k[1]])
	return " ".join(parts.slice(0, 3))


# ---------------------------------------------------------------- a row

class ExRow extends Control:
	var window: ExchangeWindow
	var index := 0
	var _hi: ColorRect
	var _icon: TextureRect
	var _name: Label
	var _level: Label
	var _quality: Label
	var _price: Label

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
		_icon.position = Vector2(4, 1)
		_icon.size = Vector2(18, 18)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_name = _cell(ExchangeWindow.C_NAME, HORIZONTAL_ALIGNMENT_LEFT)
		_level = _cell(ExchangeWindow.C_LEVEL, HORIZONTAL_ALIGNMENT_RIGHT)
		_quality = _cell(ExchangeWindow.C_QUALITY, HORIZONTAL_ALIGNMENT_RIGHT)
		_price = _cell(ExchangeWindow.C_PRICE, HORIZONTAL_ALIGNMENT_RIGHT)

	func _cell(col: Array, align: int) -> Label:
		var l := UiArt.label("", ExchangeWindow.TEXT, UiArt.CREAM)
		l.position = Vector2(float(col[0]), 2)
		l.size = Vector2(float(col[1]), 16)
		l.clip_text = true
		l.horizontal_alignment = align
		add_child(l)
		return l

	func item_id() -> String:
		return window.id_at(index)

	func refresh() -> void:
		_hi.size = size
		var id := item_id()
		var it := ItemDb.item(id) if id != "" else {}
		_icon.texture = ItemDb.icon(int(it.get("icon", 0))) if not it.is_empty() else null
		var n := String(it.get("name", "")).to_upper()
		if not it.is_empty() and int(it.get("count", 1)) > 1:
			n = "%d %s" % [int(it.count), n]
		_name.text = n
		# the name cream, red when you can't use it (the server's flag); the level in its con colour against yours
		_name.add_theme_color_override("font_color", UiArt.CREAM if bool(it.get("can_use", true)) else UiArt.RED)
		var lvl := int(it.get("level", 0))
		_level.text = str(lvl) if lvl > 0 else ""
		_level.add_theme_color_override("font_color", ItemTooltip.con_color(lvl, PlayerData.level))
		_quality.text = ("%d%%" % int(it.quality)) if int(it.get("quality", 0)) > 0 else ""
		if it.is_empty():
			_price.text = ""
		elif window.tab == "browse":
			_price.text = ExchangeWindow.money_short(int(it.get("price", 0)))
		else:
			var p := Server.listing_price(window.chest_slot(index))
			_price.text = "SET PRICE" if p < 0 else ("NOT FOR SALE" if p == 0 else ExchangeWindow.money_short(p))
		_price.add_theme_color_override("font_color", UiArt.GOLD_HI if window.tab == "browse" or _price.text != "SET PRICE" else UiArt.DIM)
		_hi.visible = id != "" and window.selected == window.key_at(index)
		tooltip_text = String(it.get("name", "")).to_upper()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER and item_id() != "":
			if window.tab == "browse":
				Server.prefetch_detail("x:%d" % index, 10, index)        # its delve text, ready for the hover box
			else:
				var s := window.chest_slot(index)
				Server.prefetch_detail(s, 1, s)
		if what == NOTIFICATION_DRAG_END:
			refresh()

	func _make_custom_tooltip(_for_text: String) -> Object:
		var id := item_id()
		if id == "":
			return null
		var it := ItemDb.item(id)
		var box: Control = ItemTooltip.make(it)
		var price := int(it.get("price", 0)) if window.tab == "browse" else Server.listing_price(window.chest_slot(index))
		if price > 0:                                      # the whole price under the stats
			if box == null:
				box = VBoxContainer.new()
				box.add_child(UiArt.label(String(it.get("name", "")), ExchangeWindow.TEXT, UiArt.CREAM))
			box.add_child(UiArt.label("PRICE: " + PlayerData.money_string(price), ExchangeWindow.TEXT, UiArt.GOLD_HI))
		return box

	func _get_drag_data(_p: Vector2) -> Variant:
		var id := item_id()
		if id == "":
			return null
		var it := ItemDb.item(id)
		var prev := TextureRect.new()
		prev.texture = ItemDb.icon(int(it.get("icon", 0)))
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.size = Vector2(32, 32) * get_global_transform().get_scale()
		prev.modulate.a = 0.85
		set_drag_preview(prev)
		# a result: from its market slot (dropped in the backpack it is bought); a listing: from its chest slot
		var slot := Server.MARKET_FIRST + index if window.tab == "browse" else window.chest_slot(index)
		return {"kind": "item", "slot": slot, "id": id, "icon": int(it.get("icon", 0)), "name": String(it.get("name", ""))}

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		var ok := window.tab == "listings" and InventorySheet.is_item(data) and PlayerData.is_backpack(int(data.slot))
		_hi.size = size
		_hi.visible = ok
		return ok

	func _drop_data(_p: Vector2, data: Variant) -> void:
		window.list_item(int(data.slot), window.chest_slot(index))

	func _gui_input(event: InputEvent) -> void:
		if item_id() == "" or not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			window.select_row(index)
			if event.double_click:
				window._do_action()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:          # the full information window
			window.select_row(index)
			if window.tab == "browse":
				Server.detail_shown(10, index)
			else:
				Server.detail_shown(1, window.chest_slot(index))
			accept_event()
