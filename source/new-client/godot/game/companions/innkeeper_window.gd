class_name InnkeeperWindow
extends ClassicWindow
## The roadside inn's innkeeper (bot plan phase 6): right-click the innkeeper.
##   YOUR COMPANIONS - what companions are and how they work (the innkeeper tells you), your slots, and each companion
##     with its class, level and where it is: SUMMON one waiting here, DISMISS one with you back to the inn, MANAGE
##     (its gear, training, tactics and stance), RELEASE one for good (asked first: whatever it carries is lost).
##   HIRE A COMPANION - the creation: race, advanced class, gender, name (or a random one from the race's names), a
##     look (RANDOMIZE), its picture turning with the class's generic level-5 weapon in hand; what it costs; HIRE.
## Companions (the rules) does the work; this only shows and asks.

const SIZE := Vector2(450, 304)
const ROW_H := 22.0

var companions: Companions
var keeper := ""
var _tabs: Array = []
var _pages: Array = []
var _intro: Label
var _slots: Label
var _list: VBoxContainer
# the hire page
var _race: OptionButton
var _cls: OptionButton
var _gender: OptionButton
var _name: LineEdit
var _blurb: Label
var _cost: Label
var _problem: Label
var _hire: Button
var _classes: Array = []
var _look := {}
var _rng := RandomNumberGenerator.new()
var _vp: SubViewport
var _figure: Fig3Figure
var _figure_key := ""
var _turn := 0.0
var _title: Label


func build() -> void:
	closable = true
	_rng.randomize()
	_title = CompanionUi.frame(self, "innkeeper", SIZE, Vector2(160, 60), "INNKEEPER")
	_tabs = CompanionUi.tabs(self, ["Your companions", "Hire a companion"], Vector2(12, 20), SIZE.x - 24, show_page)
	for i in 2:
		var page := Control.new()
		page.position = Vector2(0, 40)
		page.size = Vector2(SIZE.x, SIZE.y - 44)
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(page)
		_pages.append(page)
	_build_roster(_pages[0])
	_build_hire(_pages[1])
	show_page(0)
	PlayerData.changed.connect(_refresh_hire)


func open_for(npc_name: String, comps: Companions) -> void:
	keeper = npc_name
	companions = comps
	if not companions.changed.is_connected(refresh):
		companions.changed.connect(refresh)
	_title.text = ("%s - INNKEEPER" % npc_name).to_upper()
	show_window()
	show_page(1 if Companions.roster().is_empty() else 0)
	refresh()


func show_page(i: int) -> void:
	for k in _pages.size():
		(_pages[k] as Control).visible = k == i
	CompanionUi.select_tab(_tabs, i)
	if i == 1:
		_refresh_hire()


func refresh() -> void:
	if not visible or companions == null:
		return
	_refresh_roster()
	_refresh_hire()


# --- your companions ------------------------------------------------------------------------------------------

func _build_roster(page: Control) -> void:
	_intro = CompanionUi.text(page, "", Vector2(14, 0), Vector2(SIZE.x - 28, 62), 8, UiArt.CREAM, true)
	_slots = CompanionUi.text(page, "", Vector2(14, 64), Vector2(SIZE.x - 28, 12), 8, UiArt.GOLD)
	var box := CompanionUi.inset(page, Vector2(12, 80), Vector2(SIZE.x - 24, SIZE.y - 130))
	var sc := ScrollContainer.new()
	sc.position = Vector2(3, 3)
	sc.size = box.size - Vector2(6, 6)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(sc.size.x - 10, 0)
	_list.add_theme_constant_override("separation", 2)
	sc.add_child(_list)


func _refresh_roster() -> void:
	_intro.text = ("%s says, \"Adventurers pass through here looking for someone worth following. For a fee - your first is free - one will join you: you choose their race, their calling and their name, and they start out at the fifth season. They fight at your side, grow with you, and carry what you hand them. Right-click a companion to manage its gear, training, tactics and stance. Send one back here to wait, or release one for good - but whatever it still carries goes with it. If one falls, our healer - or any healer of the realm - can bring them back, freely until they reach the twentieth season.\"") % keeper
	var r := Companions.roster()
	var nxt := Companions.SLOT_LEVELS.filter(func(l): return int(l) > PlayerData.level)
	_slots.text = "COMPANIONS %d OF %d%s   -   NEXT HIRE: %s" % [r.size(), companions.slots_open(),
			("   (ANOTHER AT LEVEL %d)" % int(nxt[0])) if not nxt.is_empty() else "",
			"FREE" if companions.hire_cost() == 0 else PlayerData.money_string(companions.hire_cost()).to_upper()]
	for c in _list.get_children():
		c.queue_free()
	if r.is_empty():
		CompanionUi.text(_list, "NO COMPANIONS YET - HIRE ONE ON THE NEXT PAGE.", Vector2.ZERO, Vector2(380, 14), 8, CompanionUi.DIM)
		return
	for rec in r:
		_list.add_child(_row(rec))


func _row(rec: Dictionary) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(_list.custom_minimum_size.x, ROW_H)
	var inf := Companions.info(rec)
	var state := String(inf.get("state", "inn"))
	var lv := int(rec.get("level", 5))
	var s := companions.sheet_of(rec)
	if s:
		lv = s.level
	CompanionUi.text(row, String(rec.name), Vector2(4, 4), Vector2(110, 12), 9, UiArt.GOLD_HI)
	CompanionUi.text(row, "%s %d" % [String(rec.get("class_name", "")), lv], Vector2(112, 4), Vector2(100, 12), 8)
	var where: String = {"with": "WITH YOU", "inn": "AT THE INN", "dead": "DEAD"}.get(state, state.to_upper())
	CompanionUi.text(row, where, Vector2(204, 4), Vector2(70, 12), 8, CompanionUi.RED if state == "dead" else (CompanionUi.GREEN if state == "with" else CompanionUi.DIM))
	var id := int(inf.get("id", 0))
	var x := 270.0
	if state == "inn":
		CompanionUi.button(row, "Summon", Vector2(x, 3), Vector2(52, 15), func(): companions.summon(id), 8)
	elif state == "with":
		CompanionUi.button(row, "Dismiss", Vector2(x, 3), Vector2(52, 15), func(): companions.dismiss(id), 8)
	else:
		CompanionUi.text(row, "SEE THE HEALER", Vector2(x, 4), Vector2(60, 12), 7, CompanionUi.DIM)
	CompanionUi.button(row, "Manage", Vector2(x + 55, 3), Vector2(48, 15), func(): companions.manage(id), 8)
	CompanionUi.button(row, "Release", Vector2(x + 106, 3), Vector2(48, 15), func():
		UiArt.confirm(get_parent(), "RELEASE %s" % String(rec.name).to_upper(),
				"Send %s away for good? Anything still in its bags or worn is lost. The slot takes a new level-5 hire again." % rec.name,
				"RELEASE", "KEEP", func(): companions.release(id)), 8)
	return row


# --- hire a companion -----------------------------------------------------------------------------------------

func _build_hire(page: Control) -> void:
	var realm := PlayerData.realm_key()
	var races := []
	for r in CharacterFactory.RACES[realm]:
		races.append(String(r[0]))
	CompanionUi.text(page, "RACE", Vector2(14, 4), Vector2(60, 12), 8, UiArt.GOLD)
	_race = CompanionUi.option(page, races, Vector2(80, 1), Vector2(150, 16), func(_i): _race_changed())
	CompanionUi.text(page, "CLASS", Vector2(14, 24), Vector2(60, 12), 8, UiArt.GOLD)
	_cls = CompanionUi.option(page, [], Vector2(80, 21), Vector2(150, 16), func(_i): _class_changed())
	CompanionUi.text(page, "GENDER", Vector2(14, 44), Vector2(60, 12), 8, UiArt.GOLD)
	_gender = CompanionUi.option(page, ["Male", "Female"], Vector2(80, 41), Vector2(150, 16), func(_i): _random_look())
	CompanionUi.text(page, "NAME", Vector2(14, 64), Vector2(60, 12), 8, UiArt.GOLD)
	_name = CompanionUi.field(page, Vector2(80, 61), Vector2(96, 17), "NAME")
	_name.text_changed.connect(func(_t): _refresh_hire())
	CompanionUi.button(page, "Random", Vector2(180, 62), Vector2(50, 15), func(): _random_name(), 8)
	CompanionUi.button(page, "Randomize look", Vector2(80, 82), Vector2(150, 15), func(): _random_look(), 8)
	_blurb = CompanionUi.text(page, "", Vector2(14, 102), Vector2(218, 70), 8, UiArt.CREAM, true)
	_cost = CompanionUi.text(page, "", Vector2(14, 176), Vector2(218, 12), 8, UiArt.GOLD)
	_problem = CompanionUi.text(page, "", Vector2(14, 190), Vector2(218, 26), 8, CompanionUi.RED, true)
	_hire = CompanionUi.button(page, "Hire", Vector2(60, 222), Vector2(120, 18), _do_hire, 10)
	# the picture
	var box := CompanionUi.inset(page, Vector2(240, 0), Vector2(198, 246))
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.position = Vector2(2, 2)
	cont.size = box.size - Vector2(4, 4)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cont)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.size = Vector2i(396, 492)
	cont.add_child(_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 3.2)
	cam.fov = 38
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.4
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.52, 0.48)
	env.environment.ambient_light_energy = 0.9
	_vp.add_child(env)
	_race_changed()


func _race_changed() -> void:
	_classes = Companions.classes_for(PlayerData.realm_key(), _race.selected)
	_cls.clear()
	for c in _classes:
		_cls.add_item(String(c.name).to_upper())
	_cls.select(0)
	_random_look()
	_random_name()
	_class_changed()


func _class_changed() -> void:
	_figure_key = ""                                       # the weapon in hand changes with the class
	_refresh_hire()


func _random_name() -> void:
	for attempt in 30:
		var n := CharacterFactory.random_name(PlayerData.realm_key(), _race.selected, _rng)
		if Companions.name_problem(n) == "":
			_name.text = n
			break
	_refresh_hire()


func _prefix() -> String:
	return "%s_%s" % [CharacterFactory.RACES[PlayerData.realm_key()][_race.selected][2], "m" if _gender.selected == 0 else "f"]


func _random_look() -> void:
	_look = CharacterFactory.random_look(_prefix(), _rng)
	_figure_key = ""
	_refresh_hire()


func _class_id() -> int:
	return int(_classes[_cls.selected].id) if _cls.selected >= 0 and _cls.selected < _classes.size() else 0


func _refresh_hire() -> void:
	if _hire == null or companions == null or not visible:
		return
	var cid := _class_id()
	var c := ClassDb.cls(cid)
	_blurb.text = "%s - %s. Joins you at level %d with a plain %s and nothing else: give it armour, a shield and better weapons yourself (right-click it)." % [
			String(c.get("name", "")), {"PureTank": "a front-line fighter", "Tank": "a fighter", "Hybrid": "a fighter with spells",
			"ListCaster": "a spellcaster", "Rogue": "a rogue"}.get(String(c.get("class_type", "")), "an adventurer"),
			Companions.HIRE_LEVEL, String(ItemDb.item(_weapon_id()).get("name", "weapon"))]
	var cost := companions.hire_cost()
	_cost.text = "COST: " + ("FREE" if cost == 0 else PlayerData.money_string(cost).to_upper())
	var p := companions.hire_problem()
	if p == "":
		p = Companions.name_problem(_name.text.strip_edges())
	_problem.text = p
	_hire.disabled = p != ""
	_update_figure()


func _weapon_id() -> String:
	var cid := _class_id()
	return companions.generic_weapon(cid, int(ClassDb.cls(cid).get("base_class", 0))) if cid > 0 else ""


func _update_figure() -> void:
	var key := "%s|%d|%s" % [_prefix(), _class_id(), JSON.stringify(_look)]
	if key == _figure_key:
		return
	_figure_key = key
	if _figure:
		_figure.queue_free()
	_figure = Fig3Figure.new()
	if _pivot == null:
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
	_pivot.add_child(_figure)
	if _figure.load_figure(_prefix()):
		_figure.apply(_look)
	var w := ItemDb.item(_weapon_id())
	var slot := int(w.get("item_type", 10))
	var item_at := func(s: int) -> Dictionary: return w if s == (12 if slot == 12 else (13 if slot == 13 else 10)) else {}
	Player.dress(_figure, item_at, {12: "twohand", 13: "ranged"}.get(slot, "standard"), false)
	_figure.play("idle")
	_fit.call_deferred()


## Every race and size fills the picture the same, as the inventory's paper doll does (owner 2026-10-11: a troll
## didn't fit): the figure's real height (visible meshes, its race scale and size) scaled to one height on the floor.
const FIT_HEIGHT := 1.85
var _pivot: Node3D


func _fit() -> void:
	if _pivot == null or not is_inside_tree():
		return
	await get_tree().process_frame                         # transforms and the figure's own scale settled
	_pivot.scale = Vector3.ONE
	_pivot.position = Vector3.ZERO
	var lo := INF
	var hi := -INF
	for mi in _pivot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var box: AABB = _pivot.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	if hi > lo:
		var k := FIT_HEIGHT / (hi - lo)
		_pivot.scale = Vector3.ONE * k
		_pivot.position.y = -lo * k                         # feet on the floor line whatever the scale


func _process(delta: float) -> void:
	if _figure and visible and (_pages[1] as Control).visible:
		_turn += delta * 0.6
		_figure.rotation.y = sin(_turn) * 0.7


func _do_hire() -> void:
	if companions.hire(_race.selected, _gender.selected, _class_id(), _name.text.strip_edges(), _look, keeper):
		_name.text = ""
		_random_name()
		show_page(0)
		refresh()
