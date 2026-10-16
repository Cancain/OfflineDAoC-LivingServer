class_name LoadingScreen
extends CanvasLayer
## Loading screen (owner 2026-10-09): the original Dark Age of Camelot box art as the full-screen background, "ENTERING OFFLINE DAOC", the client's bronze splash bar (data/splashloadbar1 empty, splashloadbar2 full) filling as the zone
## builds, and one of the client's own loading tips (data/loading/tips.dat, 1.65-appropriate ones) under the bar,
## changing every few seconds on long loads. Fades out when the world is ready.

const UI := "res://content/ui"
const GOLD := Color(0.86, 0.71, 0.38)

var _bar: TextureProgressBar
var _root: Control
var _tip: Label
var _tips: Array = []
var _tip_time := 0.0


func _init(zone_name: String) -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(black)
	# the box art as the one full-screen background (owner: not shown twice), with a dark band at the bottom so the
	# zone name, bar and tip stay readable
	var art := TextureRect.new()
	art.texture = _tex("loading_box_art")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_root.add_child(art)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -260
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(shade)
	var label := Label.new()
	label.text = "ENTERING OFFLINE DAOC"                 # owner 2026-10-09 (not the zone name)
	var font := FontFile.new()
	font.load_dynamic_font(ProjectSettings.globalize_path(UI + "/fonts/minionpro-bold.ttf"))
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -170
	label.offset_bottom = -130
	_root.add_child(label)
	_bar = TextureProgressBar.new()
	_bar.texture_under = _tex("splashloadbar1")
	_bar.texture_progress = _tex("splashloadbar2")
	_bar.nine_patch_stretch = true
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -392
	_bar.offset_right = 392
	_bar.offset_top = -128
	_bar.offset_bottom = -86
	_root.add_child(_bar)
	var tips = JSON.parse_string(FileAccess.get_file_as_string(UI + "/loading_tips.json"))
	_tips = tips.get("tips", []) if tips is Dictionary else []
	_tip = Label.new()
	var tip_font := FontFile.new()
	tip_font.load_dynamic_font(ProjectSettings.globalize_path(UI + "/fonts/myriadpro-semibold.ttf"))
	_tip.add_theme_font_override("font", tip_font)
	_tip.add_theme_font_size_override("font_size", 22)
	_tip.add_theme_color_override("font_color", Color(0.93, 0.89, 0.78))
	_tip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_tip.add_theme_constant_override("shadow_offset_x", 2)
	_tip.add_theme_constant_override("shadow_offset_y", 2)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tip.offset_left = 160
	_tip.offset_right = -160
	_tip.offset_top = -78
	_tip.offset_bottom = -10
	_root.add_child(_tip)
	_next_tip()


func _tex(name: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path("%s/x4plus/%s.png" % [UI, name]))
	if img == null:
		img = Image.load_from_file(ProjectSettings.globalize_path("%s/original/%s.png" % [UI, name]))
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _next_tip() -> void:
	if not _tips.is_empty():
		_tip.text = "TIP: " + String(_tips[randi() % _tips.size()])


func _process(delta: float) -> void:
	_tip_time += delta
	if _tip_time > 8.0:
		_tip_time = 0.0
		_next_tip()


func set_progress(v: float) -> void:
	_bar.value = clampf(v, 0.0, 1.0)


func finish() -> void:
	set_progress(1.0)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
