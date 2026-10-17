class_name SiegeWindow
extends ClassicWindow
## The siege weapon you control (owner 2026-10-14: keep and relic sieges in the new client). The server's
## SiegeWeaponInterface fills it - the weapon's name and state, what it is doing and how long that takes, its
## ammunition - and closes it when you let go. The buttons are the client's siege commands (SiegeWeaponActionHandler):
## LOAD the chosen ammunition, ARM, AIM (at your target), FIRE, MOVE (to your ground target) / STOP, REPAIR, SALVAGE,
## RELEASE. A ram SWINGs instead of firing. Take control by using (right-clicking) a siege weapon.
## No siege window art in the classic UI files: the client's stone frame (interact.bmp) with its buttons.

const ACTIONS := ["NONE", "AIMING", "ARMING", "LOADING", "FIRING"]
const BODY := Vector2(210, 196)

var _title: Label
var _state: Label
var _ammo_list: ItemList
var _ammo: Array = []
var _time_left := 0.0
var _action := 0


func build() -> void:
	closable = true
	_title = UiArt.label("SIEGE WEAPON", 10, UiArt.GOLD_HI)
	_title.position = Vector2(8, 4)
	_title.size = Vector2(BODY.x - 16, 14)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_state = UiArt.label("", 8, UiArt.CREAM)
	_state.position = Vector2(10, 22)
	_state.size = Vector2(BODY.x - 20, 12)
	add_child(_state)
	_ammo_list = ItemList.new()
	_ammo_list.position = Vector2(10, 38)
	_ammo_list.size = Vector2(BODY.x - 20, 64)
	_ammo_list.add_theme_font_override("font", UiArt.font(true))
	_ammo_list.add_theme_font_size_override("font_size", 9)
	_ammo_list.focus_mode = Control.FOCUS_NONE
	add_child(_ammo_list)
	var buttons := [["LOAD", 1], ["ARM", 2], ["AIM", 3], ["FIRE", 4], ["MOVE", 5], ["STOP", 9], ["REPAIR", 6],
			["SALVAGE", 7], ["RELEASE", 8]]
	for i in buttons.size():
		var b := UiArt.button(String(buttons[i][0]), Vector2(60, 15), 8)
		b.position = Vector2(10 + (i % 3) * 64, 108 + (i / 3) * 19)
		var action: int = buttons[i][1]
		b.pressed.connect(func(): _command(action))
		add_child(b)
	set_window_size(BODY)


func _command(action: int) -> void:
	if Server.client == null:
		return
	var ammo := 0
	if action == 1:                                       # LOAD: the chosen ammunition's slot
		var sel := _ammo_list.get_selected_items()
		if sel.size() > 0 and int(sel[0]) < _ammo.size():
			ammo = int((_ammo[sel[0]] as Dictionary).get("index", 0))
	Server.client.call("SiegeCommand", action, ammo)


## The server's SiegeWeaponInterface packet (DaocClient: siege_window).
func show_siege(d: Dictionary) -> void:
	var nm := String(d.get("name", "siege weapon"))
	_title.text = nm.to_upper()
	_action = int(d.get("action", 0))
	_time_left = float(d.get("time", 0)) / 10.0
	_ammo = d.get("ammo", [])
	var keep := _ammo_list.get_selected_items()
	_ammo_list.clear()
	for a in _ammo:
		_ammo_list.add_item(String((a as Dictionary).get("name", "ammo")).to_upper())
	if keep.size() > 0 and int(keep[0]) < _ammo_list.item_count:
		_ammo_list.select(int(keep[0]))
	elif _ammo_list.item_count > 0:
		_ammo_list.select(0)
	_show_state()
	if not visible:
		show_window()


func _show_state() -> void:
	var what: String = ACTIONS[_action] if _action >= 0 and _action < ACTIONS.size() else "BUSY"
	_state.text = what if _time_left <= 0.05 else "%s  %.1fS" % [what, _time_left]


func _process(delta: float) -> void:
	if visible and _time_left > 0.0:
		_time_left = maxf(0.0, _time_left - delta)
		_show_state()
