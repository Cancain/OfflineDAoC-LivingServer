class_name CompanionUi
extends RefCounted
## Shared pieces of the companion windows (bot plan phase 6): the black granite frame of the in-game windows (the
## client's stone chat-box frame as a nine-patch - the Realm Options / confirm box look), gold captions, cream text,
## the bar buttons, tabs, drop-down lists and fields in the same style. Sizes in the UI's layout units.

const FRAME := "chatext"
const FRAME_RECT := Rect2(0, 64, 512, 64)
const DIM := Color(0.55, 0.52, 0.47)
const RED := Color(1.0, 0.45, 0.35)
const GREEN := Color(0.45, 0.95, 0.45)


## Make a ClassicWindow a granite window of this size (movable by its top band, the cross closes it, kept where you
## put it).
static func frame(w: ClassicWindow, id: String, size: Vector2, pos: Vector2, title: String) -> Label:
	w.resizable = true
	w.patch = [3, 12, 12, 3]
	w.min_size = size
	w.max_size = size
	w.size = size
	w.setup(id, FRAME, FRAME_RECT, pos)
	w.mouse_default_cursor_shape = Control.CURSOR_ARROW
	var t := UiArt.label(title, 11, UiArt.GOLD_HI)
	t.position = Vector2(14, 2)
	t.size = Vector2(size.x - 34, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.add_child(t)
	return t


static func text(parent: Control, s: String, pos: Vector2, size: Vector2, fs := 8, color := UiArt.CREAM, wrap := false) -> Label:
	var l := UiArt.label(s, fs, color)
	l.text = s if wrap else s.to_upper()
	l.position = pos
	if wrap:
		# wrapping on BEFORE the size: measured as one long line first, a label never shrinks back to the width
		# given and its text ran out of the window (owner 2026-10-11: the companion's Aggressive stance line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_override("font", UiArt.font(false))
		l.custom_minimum_size = Vector2(size.x, 0)
	l.size = size
	parent.add_child(l)
	if wrap:
		l.size = size
	return l


static func button(parent: Control, caption: String, pos: Vector2, size: Vector2, on_press: Callable, fs := 9) -> Button:
	var b := UiArt.button(caption, size, fs)
	b.position = pos
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## A row of tab buttons; returns them (the selected one shows pressed).
static func tabs(parent: Control, names: Array, pos: Vector2, width: float, on_select: Callable) -> Array:
	var out := []
	var w := (width - (names.size() - 1) * 3.0) / names.size()
	for i in names.size():
		var b := UiArt.button(String(names[i]), Vector2(w, 15), 9)
		b.toggle_mode = true
		b.position = pos + Vector2(i * (w + 3.0), 0)
		var idx := i
		b.pressed.connect(func(): on_select.call(idx))
		parent.add_child(b)
		out.append(b)
	return out


static func select_tab(buttons: Array, i: int) -> void:
	for k in buttons.size():
		(buttons[k] as Button).button_pressed = k == i


static func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


static func _dress(c: Control, fs: int) -> void:
	c.add_theme_font_override("font", UiArt.font(true))
	c.add_theme_font_size_override("font_size", fs)
	c.add_theme_color_override("font_color", UiArt.CREAM)
	c.add_theme_stylebox_override("normal", _style(Color(0.06, 0.055, 0.05, 0.95), UiArt.GOLD.darkened(0.4)))
	c.add_theme_stylebox_override("hover", _style(Color(0.1, 0.09, 0.07, 0.95), UiArt.GOLD.darkened(0.1)))
	c.add_theme_stylebox_override("focus", _style(Color(0.06, 0.055, 0.05, 0.95), UiArt.GOLD))
	c.add_theme_stylebox_override("pressed", _style(Color(0.1, 0.09, 0.07, 0.95), UiArt.GOLD))
	UiArt.themed(c)


## A drop-down list in the granite style.
static func option(parent: Control, items: Array, pos: Vector2, size: Vector2, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	_dress(o, 8)
	for it in items:
		o.add_item(String(it).to_upper())
	o.position = pos
	o.custom_minimum_size = size
	o.size = size
	o.item_selected.connect(on_pick)
	var pop := o.get_popup()
	pop.add_theme_font_override("font", UiArt.font(true))
	pop.add_theme_font_size_override("font_size", 8)
	pop.add_theme_color_override("font_color", UiArt.CREAM)
	pop.add_theme_stylebox_override("panel", _style(Color(0.05, 0.045, 0.04, 0.98), UiArt.GOLD.darkened(0.3)))
	parent.add_child(o)
	o.ready.connect(func(): o.size = size)
	return o


static func field(parent: Control, pos: Vector2, size: Vector2, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	_dress(e, 9)
	e.add_theme_stylebox_override("read_only", _style(Color(0.06, 0.055, 0.05, 0.95), UiArt.GOLD.darkened(0.4)))
	e.placeholder_text = placeholder
	e.position = pos
	e.custom_minimum_size = size
	e.size = size
	parent.add_child(e)
	e.ready.connect(func(): e.size = size)
	return e


## A dark inset panel (lists, the preview).
static func inset(parent: Control, pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.03, 0.028, 0.025, 0.9), UiArt.GOLD.darkened(0.55)))
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(p)
	return p
