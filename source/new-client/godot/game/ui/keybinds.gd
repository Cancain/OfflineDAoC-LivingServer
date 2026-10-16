extends Node
## Autoload "Keybinds": every bindable action of the 1.65 client (game.dll's key-config list, labels and the
## eight categories) with its default keys from the client's keyboard.dat presets (rpgdefault = "RPG", fpsdefault =
## "FPS", mmodefault = "MMO"; content/ui/keybinds.json from pipeline/client_re/keyboard_dat.py), plus quickbar slots.
## Up to two bindings per action. Any key, any mouse button (Mouse 4 / Mouse 5 / middle / wheel) and Shift / Ctrl /
## Alt combinations (owner 2026-10-09: modern bindings for gaming mice). Saved in user://keybinds.cfg.
##   Keybinds.pressed(event, "show_inventory")  - a one-shot action fired by this event (exact modifiers)
##   Keybinds.held("move_forward")              - held right now (modifiers don't block movement)

signal changed

const PATH := "user://keybinds.cfg"
const DATA := "res://content/ui/keybinds.json"
const SLOTS := 2
const QUICKBARS := 3
const QUICKBAR_SLOTS := 10

var actions: Array = []                 # [{id, label, category, presets:{rpg,fps,mmo}}]
var categories: Array = []
var bindings := {}                      # id -> [binding string, ...]
var preset := "rpg"
var path := PATH                        # the shared file, or this character's own (character-specific key bindings)
var character_specific := false
var _character := {}
var _held := {}                         # id -> [parsed binding dict]

const NAMES := {"Esc": KEY_ESCAPE, "Tab": KEY_TAB, "Space": KEY_SPACE, "Enter": KEY_ENTER, "Backspace": KEY_BACKSPACE,
	"Up": KEY_UP, "Down": KEY_DOWN, "Left": KEY_LEFT, "Right": KEY_RIGHT, "Home": KEY_HOME, "End": KEY_END,
	"PgUp": KEY_PAGEUP, "PgDn": KEY_PAGEDOWN, "Ins": KEY_INSERT, "Del": KEY_DELETE, "Caps": KEY_CAPSLOCK,
	"NumLock": KEY_NUMLOCK, "ScrollLock": KEY_SCROLLLOCK, "PrtScr": KEY_PRINT, "`": KEY_QUOTELEFT, "-": KEY_MINUS,
	"=": KEY_EQUAL, "[": KEY_BRACKETLEFT, "]": KEY_BRACKETRIGHT, ";": KEY_SEMICOLON, "'": KEY_APOSTROPHE,
	",": KEY_COMMA, ".": KEY_PERIOD, "/": KEY_SLASH, "Backslash": KEY_BACKSLASH,
	"Num0": KEY_KP_0, "Num1": KEY_KP_1, "Num2": KEY_KP_2, "Num3": KEY_KP_3, "Num4": KEY_KP_4, "Num5": KEY_KP_5,
	"Num6": KEY_KP_6, "Num7": KEY_KP_7, "Num8": KEY_KP_8, "Num9": KEY_KP_9, "Num.": KEY_KP_PERIOD,
	"Num+": KEY_KP_ADD, "Num-": KEY_KP_SUBTRACT, "Num*": KEY_KP_MULTIPLY, "Num/": KEY_KP_DIVIDE,
	"NumEnter": KEY_KP_ENTER, "LShift": KEY_SHIFT, "RShift": KEY_SHIFT, "LCtrl": KEY_CTRL, "RCtrl": KEY_CTRL,
	"LAlt": KEY_ALT, "RAlt": KEY_ALT}
const MOUSE := {"Left Mouse": MOUSE_BUTTON_LEFT, "Right Mouse": MOUSE_BUTTON_RIGHT, "Middle Mouse": MOUSE_BUTTON_MIDDLE,
	"Mouse4": MOUSE_BUTTON_XBUTTON1, "Mouse5": MOUSE_BUTTON_XBUTTON2, "Wheel Up": MOUSE_BUTTON_WHEEL_UP,
	"Wheel Down": MOUSE_BUTTON_WHEEL_DOWN, "Wheel Left": MOUSE_BUTTON_WHEEL_LEFT, "Wheel Right": MOUSE_BUTTON_WHEEL_RIGHT}


func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if data is Dictionary:
		actions = data.actions
		categories = data.categories
	# quickbar slots, the client's way (game.dll 0x4d7e4f: each bar's hover text names its modifier - Quickbar 1
	# "Modifier - None", Quickbar 2 "Modifier - Alt", Quickbar 3 "Modifier - Ctrl"; keyboard.dat AltModifier /
	# CtrlModifier): bar 1 on 1-0, bar 2 on Alt+1-0, bar 3 on Ctrl+1-0. Shift+1-0 picks quickbar 1's bank (patch
	# 1.54: "/qbar 2 switches to your second quickbar, the same as pressing Shift-2"). All rebindable.
	categories.append("Quickbars")
	for bar in range(1, QUICKBARS + 1):
		for slot in range(1, QUICKBAR_SLOTS + 1):
			var key: String = ["", "Alt+", "Ctrl+"][bar - 1] + str(slot % 10)
			actions.append({"id": "qb%d_%d" % [bar, slot], "label": "Quickbar %d Slot %d" % [bar, slot],
					"category": "Quickbars", "presets": {"rpg": [key], "fps": [key], "mmo": [key]}})
	for bank in range(1, QUICKBAR_SLOTS + 1):
		var key := "Shift+" + str(bank % 10)
		actions.append({"id": "qbank_%d" % bank, "label": "Quickbar Bank %d" % bank, "category": "Quickbars",
				"presets": {"rpg": [key], "fps": [key], "mmo": [key]}})
	load_bindings()


## Key bindings are shared by all characters; a character can opt into its own set (Options > CONTROLS,
## "CHARACTER-SPECIFIC KEY BINDINGS", like WoW's). Called by PlayerData when a character enters the world.
func use_character(c: Dictionary) -> void:
	_character = c
	character_specific = bool(c.get("own_keybinds", false))
	path = _character_path() if character_specific else PATH
	load_bindings()
	changed.emit()


func set_character_specific(on: bool) -> void:
	if _character.is_empty():
		return
	character_specific = on
	_character["own_keybinds"] = on
	PlayerData.save_character()
	if on:
		path = _character_path()
		if not FileAccess.file_exists(path):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			save_bindings()                                # starts as a copy of the shared keys
	else:
		path = PATH
	load_bindings()
	changed.emit()


func _character_path() -> String:
	var who := "%s_%s" % [String(Accounts.account if Accounts.account != "" else "local"), String(_character.get("name", "x"))]
	return "user://keybinds/%s.cfg" % who.to_lower().validate_filename()


func load_bindings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(path) == OK
	preset = String(cfg.get_value("keybinds", "preset", "rpg")) if ok else "rpg"
	# version 2 (2026-10-09): quickbars 2 / 3 gained their Alt / Ctrl keys and the Shift bank keys; older saves kept
	# those empty, so they take the new defaults once
	var old := int(cfg.get_value("keybinds", "version", 1)) < 2 if ok else false
	for a in actions:
		var saved = cfg.get_value("bindings", a.id, null) if ok else null
		var quick := String(a.id).begins_with("qb2_") or String(a.id).begins_with("qb3_") or String(a.id).begins_with("qbank_")
		if saved is Array and not (old and quick and (saved as Array).is_empty()):
			bindings[a.id] = (saved as Array).duplicate()
		else:
			bindings[a.id] = (a.presets.get(preset, []) as Array).duplicate()
	_apply()


func save_bindings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("keybinds", "preset", preset)
	cfg.set_value("keybinds", "version", 2)
	for id in bindings:
		cfg.set_value("bindings", id, bindings[id])
	cfg.save(path)


## Reset every action to one of the client's presets ("rpg", "fps", "mmo").
func use_preset(name: String) -> void:
	preset = name
	for a in actions:
		bindings[a.id] = (a.presets.get(name, []) as Array).duplicate()
	_apply()
	save_bindings()


## Bind slot (0 or 1) of an action; the binding is taken from any other action that had it. Returns that action's
## label ("" if none) so the window can say "MOVED FROM ...".
func bind(id: String, slot: int, binding: String) -> String:
	var stolen := ""
	for other in bindings:
		var list: Array = bindings[other]
		if binding != "" and list.has(binding) and not (other == id and list.find(binding) == slot):
			list.erase(binding)
			stolen = label_of(other)
	var mine: Array = bindings.get(id, [])
	while mine.size() <= slot:
		mine.append("")
	mine[slot] = binding
	while mine.size() > 0 and mine[mine.size() - 1] == "":
		mine.pop_back()
	bindings[id] = mine
	_apply()
	save_bindings()
	return stolen


func label_of(id: String) -> String:
	for a in actions:
		if a.id == id:
			return String(a.label)
	return id


## The binding string for an input event ("Shift+F1", "Mouse4", "Ctrl+Wheel Up"), or "" for events that can't bind.
func describe(event: InputEvent) -> String:
	var mods := ""
	if event is InputEventWithModifiers:
		if event.ctrl_pressed: mods += "Ctrl+"
		if event.alt_pressed: mods += "Alt+"
		if event.shift_pressed: mods += "Shift+"
	if event is InputEventKey:
		var k: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if k in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return ""                                    # a modifier alone waits for the real key
		for n in NAMES:
			if NAMES[n] == k:
				return mods + n
		return mods + OS.get_keycode_string(k)
	if event is InputEventMouseButton:
		for n in MOUSE:
			if MOUSE[n] == event.button_index:
				return mods + n
		return mods + "Mouse%d" % event.button_index
	return ""


func _parse(binding: String) -> Dictionary:
	var parts := binding.split("+")
	var d := {"shift": false, "ctrl": false, "alt": false, "key": KEY_NONE, "mouse": 0}
	var main := binding
	if parts.size() > 1 and binding != "Num+":
		main = parts[parts.size() - 1] if not binding.ends_with("+") else "+"
		for i in parts.size() - 1:
			d[String(parts[i]).to_lower()] = true
		if binding.ends_with("Num+"):
			main = "Num+"
	if MOUSE.has(main):
		d.mouse = MOUSE[main]
	elif NAMES.has(main):
		d.key = NAMES[main]
	elif main.length() == 1 or main.begins_with("F"):
		d.key = OS.find_keycode_from_string(main)
	return d


func _apply() -> void:
	_held.clear()
	for id in bindings:
		var list := []
		for b in bindings[id]:
			if String(b) != "":
				list.append(_parse(String(b)))
		_held[id] = list
	changed.emit()


## One-shot: did this event press the action? Modifiers must match exactly (F1 and Shift+F1 are different actions).
func pressed(event: InputEvent, id: String) -> bool:
	if not (event.is_pressed() and not event.is_echo()):
		return false
	for d in _held.get(id, []):
		if _event_is(event, d, true):
			return true
	return false


## Held: is any binding of the action down now? Extra modifiers don't break it (Shift walk while moving forward).
func held(id: String) -> bool:
	for d in _held.get(id, []):
		var down := false
		if d.mouse != 0:
			down = Input.is_mouse_button_pressed(d.mouse)
		elif d.key != KEY_NONE:
			down = Input.is_physical_key_pressed(d.key) or Input.is_key_pressed(d.key)
		if down and (not d.shift or Input.is_key_pressed(KEY_SHIFT)) and (not d.ctrl or Input.is_key_pressed(KEY_CTRL)) \
				and (not d.alt or Input.is_key_pressed(KEY_ALT)):
			return true
	return false


## Which action (id) this event presses, or "".
func action_for(event: InputEvent) -> String:
	for id in _held:
		if pressed(event, id):
			return id
	return ""


func _event_is(event: InputEvent, d: Dictionary, exact: bool) -> bool:
	if event is InputEventWithModifiers and exact:
		if event.shift_pressed != d.shift or event.ctrl_pressed != d.ctrl or event.alt_pressed != d.alt:
			return false
	if event is InputEventKey and d.key != KEY_NONE:
		var k: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return k == d.key
	if event is InputEventMouseButton and d.mouse != 0:
		return event.button_index == d.mouse
	return false


## "W / UP" style text for the window.
func text(id: String) -> String:
	var list: Array = bindings.get(id, [])
	return " / ".join(list).to_upper() if list.size() > 0 else "-"
