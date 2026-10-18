class_name GameMenu
extends CanvasLayer
## Temporary in-game menu (Esc) until the real "new old" UI is designed: movement mode and quit.
## Settings persist in user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"
const FPS_CAPS := [0, 30, 60, 75, 90, 120, 144, 165, 240, -1]   # 0 = monitor refresh (vsync), -1 = unlimited

const VOLUMES := [["Master", "Volume"], ["Effects", "Sound effects"], ["Ambient", "Ambience"], ["Music", "Music"]]

signal movement_changed(mode: String)

var settings := ConfigFile.new()
var _panel: PanelContainer
var _movement: OptionButton
var _fps: OptionButton


func _ready() -> void:
	layer = 10
	settings.load(SETTINGS_PATH)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.position = Vector2(-190, -170)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Offline DAoC Rebuilt"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Movement"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_movement = OptionButton.new()
	_movement.add_item("Modern MMO (WoW-style)")
	_movement.set_item_metadata(0, "modern")
	_movement.add_item("Classic DAoC")
	_movement.set_item_metadata(1, "classic")
	_movement.select(1 if movement_mode() == "classic" else 0)
	_movement.item_selected.connect(_on_movement)
	row.add_child(_movement)
	box.add_child(row)

	# frame-rate cap only: no graphics settings change (owner, 2026-10-09)
	var fps_row := HBoxContainer.new()
	var fps_label := Label.new()
	fps_label.text = "FPS cap"
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	_fps = OptionButton.new()
	for cap in FPS_CAPS:
		_fps.add_item("Monitor refresh (vsync)" if cap == 0 else ("Unlimited (no vsync)" if cap < 0 else "%d FPS" % cap))
	var saved_cap := fps_cap()
	_fps.select(maxi(0, FPS_CAPS.find(saved_cap)))
	_fps.item_selected.connect(_on_fps)
	fps_row.add_child(_fps)
	box.add_child(fps_row)
	apply_fps_cap(saved_cap)

	# volume: master / ambience + effects / music (client sound categories: sound_type 1+3 vs 2 and mp3s)
	for v in VOLUMES:
		var vrow := HBoxContainer.new()
		var vlabel := Label.new()
		vlabel.text = v[1]
		vlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vrow.add_child(vlabel)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.custom_minimum_size = Vector2(160, 0)
		slider.value = volume(v[0])
		slider.value_changed.connect(func(val: float): _on_volume(v[0], val))
		vrow.add_child(slider)
		box.add_child(vrow)

	var hint := Label.new()
	hint.text = "Player only. Classic: A/D turn, Q/E slow side-step, slow backward walk."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(close)
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	add_child(_panel)
	_panel.visible = false


func fps_cap() -> int:
	return int(settings.get_value("display", "fps_cap", 0))


## 0 = follow the monitor's refresh with vsync, >0 = cap at that many frames (vsync stays on), <0 = unlimited, no vsync.
func apply_fps_cap(cap: int) -> void:
	if cap < 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		Engine.max_fps = cap


func _on_fps(index: int) -> void:
	var cap: int = FPS_CAPS[index]
	settings.set_value("display", "fps_cap", cap)
	settings.save(SETTINGS_PATH)
	apply_fps_cap(cap)


func volume(bus: String) -> float:
	var fallback = settings.get_value("audio", "ambient", 100) if bus == "Effects" else 100
	return float(settings.get_value("audio", bus.to_lower(), fallback))


func apply_volumes() -> void:
	for v in VOLUMES:
		var i := AudioServer.get_bus_index(v[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume(v[0]) / 100.0, 0.0001)))


func _on_volume(bus: String, val: float) -> void:
	settings.set_value("audio", bus.to_lower(), val)
	settings.save(SETTINGS_PATH)
	apply_volumes()


func movement_mode() -> String:
	return String(settings.get_value("player", "movement", "modern"))


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_panel.visible = false


func _on_movement(index: int) -> void:
	var mode := String(_movement.get_item_metadata(index))
	settings.set_value("player", "movement", mode)
	settings.save(SETTINGS_PATH)
	movement_changed.emit(mode)
