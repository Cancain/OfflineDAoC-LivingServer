class_name UiArt
extends RefCounted
## Shared look for the 1.65 in-game interface: the client's original UI bitmaps (content/ui/classic, x4plus at 4x,
## pipeline/build_ui_classic.py) and the "new old" text style (NEW OLD UI DIRECTION.md: Minion Pro bold, ALL CAPS,
## gold headings, cream text, drop shadow). Art coordinates are in the original bitmap pixels (x4plus = x4).

const DIR := "res://content/ui/classic"
const FONT_DIR := "res://content/ui/fonts"
const K := 4.0                                   # x4plus scale
const GOLD := Color(0.86, 0.71, 0.38)
const GOLD_HI := Color(1.0, 0.85, 0.45)
const CREAM := Color(0.93, 0.89, 0.78)
const DIM := Color(0.6, 0.57, 0.52)
const RED := Color(1.0, 0.42, 0.35)
const GREEN := Color(0.45, 0.95, 0.45)
const SHADOW := Color(0, 0, 0, 0.95)

## Where the interface keeps its settings; test runs (--ui-test) use their own file so they never move the
## owner's windows.
static var settings_path := "user://settings.cfg"
static var _tex := {}
static var _fonts := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var up := "%s/x4plus/%s.png" % [DIR, name]
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(up)) if FileAccess.file_exists(up) else null
		if img == null:
			img = Image.load_from_file(ProjectSettings.globalize_path("%s/original/%s.png" % [DIR, name]))
			if img:
				img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_LANCZOS)
		if img:
			img.generate_mipmaps()
		_tex[name] = ImageTexture.create_from_image(img) if img else null
	return _tex[name]


## A region of a classic bitmap, in original pixels.
static func region(name: String, r: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex(name)
	a.region = Rect2(r.position * K, r.size * K)
	a.filter_clip = true
	return a


static func font(bold := true) -> FontFile:
	var file := "minionpro-bold.ttf" if bold else "minionpro-regular.ttf"
	if not _fonts.has(file):
		var f := FontFile.new()
		f.load_dynamic_font(ProjectSettings.globalize_path("%s/%s" % [FONT_DIR, file]))
		# the whole UI is drawn scaled (800x600 layout units -> the window); distance-field glyphs stay sharp at any
		# scale instead of a small bitmap font blown up (owner: "text too low res")
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = 8
		f.msdf_size = 48
		_fonts[file] = f
	return _fonts[file]


## A caps label in the new-old style.
static func label(text: String, size := 11, color := CREAM, bold := true) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	themed(l)
	return l


## Make a control measure itself with its own font now. Outside the scene tree Godot sizes text controls with the
## default 16 px font, and a size set then never shrinks back: the owner's low status name, the 31-unit-tall chat
## input, the oversized buttons. Call after the theme overrides, before setting the size.
static func themed(c: Control) -> Control:
	c.notification(Control.NOTIFICATION_THEME_CHANGED)
	return c


## A picture of a classic bitmap (or a region of it) sized in original pixels.
static func picture(name: String, r := Rect2()) -> TextureRect:
	var t := TextureRect.new()
	t.texture = region(name, r) if r.size != Vector2.ZERO else tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = r.size if r.size != Vector2.ZERO else Vector2(t.texture.get_width(), t.texture.get_height()) / K
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A text button in the client's own bar look - the pregame bar (misc_pieces_new: normal / hover / pressed /
## disabled, x4plus), the same buttons as the character screens - bold caps text shrunk to fit.
static func button(text: String, size := Vector2(56, 14), font_size := 9) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var caption := text.to_upper()
	var fs := font_size
	# shrink until the caption fits inside the bar art's rounded ends, outline included (owner: no cut-off text)
	while fs > 6 and font(true).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 4 > size.x - minf(18.0, size.x * 0.12):
		fs -= 1
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", GOLD_HI)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.75, 0.0))
	b.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.75, 0.0))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.38))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 2)
	var states := {"normal": 0, "hover": 1, "pressed": 2, "hover_pressed": 2, "disabled": 3}
	for k in states:
		b.add_theme_stylebox_override(k, bar_style(states[k]))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	themed(b)
	# text and size last: a Button sizes itself to its text, and with the text set first it measured it in Godot's
	# default 16 px font and kept that size (the owner's cut-off / overlapping buttons)
	b.text = caption
	b.custom_minimum_size = size
	b.size = size
	b.ready.connect(func(): b.size = size)                 # theme overrides only apply inside the tree
	return b


## A yes / no box in the black granite of the client's windows (owner 2026-10-10: not the engine's grey dialog): the
## chat box frame (chatext) as a nine-patch over a dimmed screen, gold title, cream text, the bar buttons. A click
## outside the box is the cancel.
static func confirm(parent: Control, title: String, text: String, ok_text: String, cancel_text: String,
		on_ok: Callable, on_cancel := Callable()) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(shade)
	var w := 300.0
	var h := 112.0 if title != "" else 96.0
	var box := Control.new()
	box.size = Vector2(w, h)
	var area := parent.size if parent.size != Vector2.ZERO else parent.get_viewport_rect().size
	box.position = ((area - box.size) * 0.5).floor()
	shade.add_child(box)
	var holder := Control.new()
	holder.scale = Vector2(0.25, 0.25)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var np := NinePatchRect.new()
	np.texture = tex("chatext")
	np.region_rect = Rect2(0, 64 * K, 512 * K, 64 * K)
	var m := [3, 12, 12, 3]
	var sides := [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
	for i in 4:
		np.set_patch_margin(sides[i], int(m[i] * K))
	np.size = box.size * 4.0
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(np)
	box.add_child(holder)
	var y := 16.0
	if title != "":
		var t := label(title.to_upper(), 11, GOLD_HI)
		t.position = Vector2(0, y)
		t.size = Vector2(w, 14)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
		y += 18.0
	var body := label(text.to_upper(), 9, CREAM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # before the size: it wraps to the box, not the text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(w - 28, 0)
	box.add_child(body)
	body.position = Vector2(14, y)
	body.size = Vector2(w - 28, 36)
	var done := func(ok: bool):
		shade.queue_free()
		if ok:
			on_ok.call()
		elif on_cancel.is_valid():
			on_cancel.call()
	var yes := button(ok_text, Vector2(84, 16), 9)
	yes.position = Vector2(w * 0.5 - 94, h - 30)
	yes.pressed.connect(done.bind(true))
	box.add_child(yes)
	var no := button(cancel_text, Vector2(84, 16), 9)
	no.position = Vector2(w * 0.5 + 10, h - 30)
	no.pressed.connect(done.bind(false))
	box.add_child(no)
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not Rect2(box.position, box.size).has_point(e.position):
			done.call(false))
	return shade


static func bar_style(state: int) -> StyleBox:
	if not _tex.has("_bar"):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://content/pregame/ui/small/misc_pieces_new.png"))
		if img:
			img.generate_mipmaps()
		_tex["_bar"] = ImageTexture.create_from_image(img) if img else null
	var t: Texture2D = _tex["_bar"]
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.12, 0.1, 0.08)
		f.border_color = GOLD.darkened(0.3)
		f.set_border_width_all(1)
		return f
	var s := StyleBoxTexture.new()
	s.texture = t
	s.region_rect = Rect2(0, (105 + state * 22) * 4, 102 * 4, 22 * 4)
	s.set_content_margin_all(2)
	return s


## Tooltips the client's way: a short caption in a dark box (the client's tooltips.csv is captions; item details
## live in the information window). Tooltips are their own little windows, so the size is screen pixels.
static func tooltip_theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.02, 0.02, 0.85)         # the client's caption box: dark, thin grey rim
	panel.border_color = Color(0.55, 0.55, 0.5, 0.9)
	panel.set_border_width_all(1)
	panel.content_margin_left = 7
	panel.content_margin_right = 7
	panel.content_margin_top = 3
	panel.content_margin_bottom = 4
	t.set_stylebox("panel", "TooltipPanel", panel)
	t.set_font("font", "TooltipLabel", font(true))
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_color("font_shadow_color", "TooltipLabel", SHADOW)
	t.set_constant("shadow_offset_x", "TooltipLabel", 1)
	t.set_constant("shadow_offset_y", "TooltipLabel", 1)
	return t
