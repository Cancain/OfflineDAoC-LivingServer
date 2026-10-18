class_name EmblemWindow
extends ClassicWindow
## The guild emblem picker (the client's emblempick.bmp, 219 x 288 - game.dll "EmblemPicker"; owner 2026-10-17: a
## high-quality guild UI). The server opens it (EmblemDialogue 0xE2: the emblemer, /gc emblem); SET EMBLEM sends the
## choice back (EmblemDialogResponse: primary, secondary, pattern, logo - the server takes it from the guild leader
## only). A turning shield shows the emblem as it will be worn (Emblems.shield_material); pattern, the two colours
## (patterns.csv) and the logo (insignia.csv) by arrows, the logos also as a grid.

const SIZE := Vector2(219, 288)
const PREVIEW_SHIELD := 60                         # the metal heater shield (an emblem shield: weapons.json "emblem")
const GRID_COLS := 8

var primary := 0
var secondary := 0
var pattern := 0
var logo := 1

var _view: SubViewport
var _shield_holder: Node3D
var _shield: Node3D
var _values := {}
var _swatches := {}
var _grid: GridContainer
var _logo_buttons := {}
var _spin := 0.0


func build() -> void:
	closable = true
	var title := UiArt.label("GUILD EMBLEM", 11, UiArt.GOLD_HI)
	title.position = Vector2(10, 15)
	title.size = Vector2(SIZE.x - 20, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	# the preview: a shield turning in its own little world
	var box := SubViewportContainer.new()
	box.position = Vector2(10, 34)
	box.size = Vector2(84, 108)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.size = Vector2i(168, 216)
	box.add_child(_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, 25, 0)
	_view.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 1.55)
	cam.fov = 40
	_view.add_child(cam)
	_shield_holder = Node3D.new()
	_view.add_child(_shield_holder)
	# the four choices
	var rows := [["pattern", "PATTERN"], ["primary", "FIELD"], ["secondary", "CHARGE"], ["logo", "LOGO"]]
	for i in rows.size():
		var key: String = rows[i][0]
		var y := 36.0 + i * 26.0
		var l := UiArt.label(rows[i][1], 8, UiArt.GOLD)
		l.position = Vector2(100, y)
		add_child(l)
		var prev := UiArt.button("<", Vector2(14, 13), 8)
		prev.position = Vector2(100, y + 11)
		prev.pressed.connect(func(): _step(key, -1))
		add_child(prev)
		var nxt := UiArt.button(">", Vector2(14, 13), 8)
		nxt.position = Vector2(195, y + 11)
		nxt.pressed.connect(func(): _step(key, 1))
		add_child(nxt)
		if key == "primary" or key == "secondary":
			var sw := ColorRect.new()
			sw.position = Vector2(117, y + 12)
			sw.size = Vector2(11, 11)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(sw)
			_swatches[key] = sw
		var v := UiArt.label("", 8, UiArt.CREAM)
		v.position = Vector2(130 if key in ["primary", "secondary"] else 117, y + 12)
		v.size = Vector2(64 if key in ["primary", "secondary"] else 77, 12)
		v.clip_text = true
		add_child(v)
		_values[key] = v
	# every logo
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(10, 148)
	scroll.size = Vector2(SIZE.x - 20, 104)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiArt.themed(scroll)
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 1)
	_grid.add_theme_constant_override("v_separation", 1)
	scroll.add_child(_grid)
	var ok := UiArt.button("SET EMBLEM", Vector2(72, 16), 8)
	ok.position = Vector2(30, 260)
	ok.tooltip_text = "MAKE THIS YOUR GUILD'S EMBLEM (GUILD LEADER ONLY)"
	ok.pressed.connect(_choose)
	add_child(ok)
	var cancel := UiArt.button("CANCEL", Vector2(72, 16), 8)
	cancel.position = Vector2(117, 260)
	cancel.pressed.connect(hide_window)
	add_child(cancel)


## Open on an emblem (the guild's current one, 0: a first choice).
func open(emblem: int) -> void:
	if emblem > 0:
		var d := Emblems.decode(emblem)
		primary = int(d.primary)
		secondary = int(d.secondary)
		pattern = int(d.pattern)
		logo = maxi(1, int(d.logo))
	if _grid.get_child_count() == 0:
		for id in Emblems.logo_ids():
			var b := TextureButton.new()
			b.texture_normal = Emblems.logo_texture(int(id))
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			b.custom_minimum_size = Vector2(23, 23)
			b.tooltip_text = ("%s (%d)" % [Emblems.logo_name(int(id)), int(id)]).strip_edges().to_upper()
			b.focus_mode = Control.FOCUS_NONE
			var pick := int(id)
			b.pressed.connect(func():
				logo = pick
				_refresh())
			_grid.add_child(b)
			_logo_buttons[int(id)] = b
	show_window()
	_refresh()


func emblem() -> int:
	return Emblems.encode(logo, pattern, primary, secondary)


func _step(key: String, by: int) -> void:
	match key:
		"pattern": pattern = posmod(pattern + by, 4)
		"primary": primary = posmod(primary + by, 16)
		"secondary": secondary = posmod(secondary + by, 8)
		"logo":
			var ids := Emblems.logo_ids()
			var i := ids.find(logo)
			logo = int(ids[posmod(i + by, ids.size())]) if not ids.is_empty() else 1
	_refresh()


func _refresh() -> void:
	_values.pattern.text = "%d OF 4" % (pattern + 1)
	_values.primary.text = Emblems.color_name("primary", primary).to_upper()
	_values.secondary.text = Emblems.color_name("secondary", secondary).to_upper()
	var nm := Emblems.logo_name(logo)
	_values.logo.text = (nm if nm != "" else "#%d" % logo).to_upper()
	_swatches.primary.color = Emblems.color("primary", primary)
	_swatches.secondary.color = Emblems.color("secondary", secondary)
	for id in _logo_buttons:                              # the chosen logo lit gold, the rest as they are
		(_logo_buttons[id] as TextureButton).modulate = Color(1.0, 0.85, 0.45) if int(id) == logo else Color(0.82, 0.82, 0.82)
	if _shield:
		_shield.queue_free()
	_shield = WeaponModels.make(PREVIEW_SHIELD)
	if _shield:
		WeaponModels.set_emblem(_shield, PREVIEW_SHIELD, emblem())
		var stand := Node3D.new()                         # (NIF units on its back: stood up to face the camera)
		stand.rotation_degrees = Vector3(-90, 0, 0)
		stand.add_child(_shield)
		_shield_holder.add_child(stand)
		# centred on its middle (its origin is the grip) and sized to the view
		var box := AABB()
		var first := true
		for mi in _shield.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		if not first and box.size.y > 0.0:
			var k := 1.0 / maxf(box.size.y, box.size.x * 1.25)
			stand.scale = Vector3.ONE * k
			stand.position = -box.get_center() * k
		_shield = stand


func _process(delta: float) -> void:
	if visible and _shield_holder:
		_spin += delta
		_shield_holder.rotation.y = sin(_spin * 0.8) * 0.45


func _choose() -> void:
	if Server.active and Server.client:
		Server.client.call("EmblemChoice", primary, secondary, pattern, logo)
	hide_window()
