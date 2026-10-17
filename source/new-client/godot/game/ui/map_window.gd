class_name MapWindow
extends ClassicWindow
## The map window (M): the client's own map system (owner 2026-10-09 - post-1.65, the in-game map came with test
## 1.71d), in the classic stone frame. pipeline/build_maps.py -> content/maps/maps.json + the client's painted maps:
##   - a zone map (z###) for every zone, area maps (z###_NN) for towns / dungeon wings inside a zone, and the region
##     maps (r###) with each zone's square on them - click a square to open that zone;
##   - the dropdown finds any map (realm overview, its zones, their areas);
##   - FOLLOW keeps the map on where you are (the zone, or the area map you stand in); picking a map turns it off.
## The player's arrow shows on any map that holds the spot; quest marks on zone / area maps.

const MAP_SIZE := 260.0
const TOP := 43.0                         # title + dropdown row above the picture
var player: Node3D
var zone_size := 1638.4                   # current zone's size (metres)
var current_zone := -1
var marks: Array = []                     # quest marks (QuestMarkers): [{at: Vector2 world x / z, kind: "!" / "?" / "step"}]
var follow := true
var shown := {}                           # {kind: "zone" / "area" / "region", id, area}
var _maps := {}
var _view: MapView
var _title: Label
var _pick: OptionButton
var _follow_btn: Button
var _entries: Array = []                  # dropdown index -> shown dict ({} = header)
var _tex := {}


func build() -> void:
	closable = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/maps.json"))
	_maps = parsed if parsed is Dictionary else {}
	_title = UiArt.label("", 11, UiArt.GOLD_HI)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_pick = _dropdown()
	add_child(_pick)
	_follow_btn = UiArt.button("Follow", Vector2(58, 18), 9)
	_follow_btn.toggle_mode = true
	_follow_btn.button_pressed = follow
	_follow_btn.toggled.connect(func(on: bool):
		follow = on
		if on:
			_follow_now())
	add_child(_follow_btn)
	_view = MapView.new()
	_view.window = self
	add_child(_view)
	_fill_dropdown()
	_layout()
	resized.connect(_layout)
	PlayerData.quests_changed.connect(_on_quests_changed)


func _layout() -> void:
	if _view == null:
		return
	var w := size.x - 27.0
	var h := size.y - TOP - 8.0 - 33.0 + 21.0
	var side := maxf(64.0, minf(w, h))
	_title.position = Vector2(12, 3)                       # in the frame's top band (was a gap above it)
	_title.size = Vector2(size.x - 24.0, 16)
	_pick.position = Vector2(12, 21)
	_pick.size = Vector2(size.x - 24.0 - 72.0, 18)
	_follow_btn.position = Vector2(size.x - 22.0 - 58.0, 21)  # clear of the frame's right edge
	_view.position = Vector2(12 + (w - side) * 0.5, TOP)
	_view.size = Vector2(side, side)


## The zone the player is in now (zone_viewer at every zone load).
func set_current_zone(zone_id: int, size_m: float) -> void:
	current_zone = zone_id
	zone_size = size_m
	_fill_dropdown()
	if follow or shown.is_empty():
		_follow_now()


## Old entry point (kept for the zone viewer's older call): the zone id from the zone folder's name.
func set_zone(map_path: String, size_m: float, _title_text: String) -> void:
	set_current_zone(int(map_path.get_base_dir().get_file().trim_prefix("zone")), size_m)


func _zone(z: int) -> Dictionary:
	return (_maps.get("zones", {}) as Dictionary).get(str(z), {})


## The square of a zone its map shows, in zone units: the whole zone, or - the capitals and dungeons - the square their
## region gives (regions.dat zoneK_offsetx / _offsety / _width / _height; game.dll's map takes a spot minus that offset
## over that size, and an area's rect inside it). Owner 2026-10-14: Jordheim's map put you, the bots and the quest
## marks way off - it was drawn over the whole zone.
func map_rect(z: int) -> Rect2:
	var r = _zone(z).get("map_rect")
	if r is Array and (r as Array).size() == 4:
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var units := _zone_size_of(z) / 0.025
	return Rect2(0.0, 0.0, units, units)


func _region(r: int) -> Dictionary:
	return (_maps.get("regions", {}) as Dictionary).get(str(r), {})


## The player's spot in zone units: x, y on the map, height.
func _player_units() -> Vector3:
	var p := player
	if p == null:
		return Vector3(-1, -1, 0)
	return Vector3(p.global_position.x, p.global_position.z, p.global_position.y) / 0.025


func _area_at(z: int, u: Vector3) -> int:
	var areas: Array = _zone(z).get("areas", [])
	for i in areas.size():
		var a: Dictionary = areas[i]
		var r: Array = a.rect
		var mr := map_rect(z)                                   # an area's rect is inside the zone map's square
		var x := u.x - mr.position.x
		var y := u.y - mr.position.y
		if x <= float(r[0]) or y <= float(r[1]) or x > float(r[0]) + float(r[2]) or y > float(r[1]) + float(r[3]):
			continue
		# a level of a dungeon: its floor (area z) and the height above it (depth) - game.dll 0x530a31: z > area z
		# and z <= area z + depth (the levels stack upward: Darkness Falls' 19126 + 1675 = the next one's 20801)
		if a.has("z") and a.has("depth") and int(a.z) != -1 and int(a.depth) != -1:
			if u.z <= float(a.z) or u.z > float(a.z) + float(a.depth):
				continue
		return i
	return -1


func _follow_now() -> void:
	if current_zone < 0:
		return
	var i := _area_at(current_zone, _player_units())
	_show({"kind": "area", "id": current_zone, "area": i} if i >= 0 else {"kind": "zone", "id": current_zone}, false)


func _process(_delta: float) -> void:
	if not visible:
		return
	if follow and current_zone >= 0:
		var i := _area_at(current_zone, _player_units())
		var want := {"kind": "area", "id": current_zone, "area": i} if i >= 0 else {"kind": "zone", "id": current_zone}
		if want != shown:
			_show(want, false)
	_view.queue_redraw()


func _show(what: Dictionary, picked: bool) -> void:
	shown = what
	var title := ""
	var pic := ""
	match String(what.get("kind", "")):
		"region":
			var r := _region(int(what.id))
			title = String(r.get("name", ""))
			pic = String(r.get("map", ""))
		"area":
			var a: Dictionary = (_zone(int(what.id)).get("areas", []) as Array)[int(what.area)]
			title = String(a.get("name", "")) if String(a.get("name", "")) != "" else String(_zone(int(what.id)).get("name", ""))
			pic = String(a.get("map", ""))
		_:
			title = String(_zone(int(what.id)).get("name", ""))
			pic = String(_zone(int(what.id)).get("map", ""))
	_title.text = title.to_upper()
	_view.texture = _texture(pic)
	var idx := _entries.find(what)
	if idx >= 0 and _pick.selected != idx:
		_pick.select(idx)
	if picked and follow:
		follow = false
		_follow_btn.set_pressed_no_signal(false)


func _texture(name: String) -> Texture2D:
	if name == "":
		return null
	if not _tex.has(name):
		var path := "res://content/maps/x4plus/" + name
		if not FileAccess.file_exists(path):
			path = "res://content/maps/original/" + name
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
		if img:
			img.generate_mipmaps()
		_tex[name] = ImageTexture.create_from_image(img) if img else null
	return _tex[name]


func _dropdown() -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.clip_text = true
	o.fit_to_longest_item = false
	o.add_theme_font_override("font", UiArt.font(true))
	o.add_theme_font_size_override("font_size", 9)
	o.add_theme_color_override("font_color", UiArt.CREAM)
	o.add_theme_color_override("font_hover_color", UiArt.GOLD_HI)
	o.add_theme_stylebox_override("normal", UiArt.bar_style(0))
	o.add_theme_stylebox_override("hover", UiArt.bar_style(1))
	o.add_theme_stylebox_override("pressed", UiArt.bar_style(2))
	o.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UiArt.themed(o)
	var pop := o.get_popup()
	pop.add_theme_font_override("font", UiArt.font(true))
	pop.add_theme_font_size_override("font_size", 13)
	pop.add_theme_color_override("font_color", UiArt.CREAM)
	pop.add_theme_color_override("font_hover_color", UiArt.GOLD_HI)
	pop.add_theme_color_override("font_separator_color", UiArt.GOLD_HI)
	pop.add_theme_color_override("font_disabled_color", UiArt.GOLD_HI)
	pop.max_size = Vector2i(0, 520)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.065, 0.06, 0.97)
	panel.border_color = UiArt.GOLD.darkened(0.3)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(4)
	pop.add_theme_stylebox_override("panel", panel)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(0.3, 0.22, 0.1, 0.9)
	pop.add_theme_stylebox_override("hover", hov)
	o.item_selected.connect(func(i: int):
		if i >= 0 and i < _entries.size() and not (_entries[i] as Dictionary).is_empty():
			_show(_entries[i], true))
	return o


## Your realm only (owner 2026-10-09): its capital city at the very top, then its classic and Shrouded Isles open
## world zones in alphabetical order. No dungeons, no other realms. Inside a dungeon: that dungeon's maps only.
const REALM_REGIONS := {1: [1, 51], 2: [100, 151], 3: [200, 181]}
const CAPITALS := {1: 26, 2: 120, 3: 209}


func _fill_dropdown() -> void:
	_pick.clear()
	_entries.clear()
	var realm := PlayerData.realm_id()
	var here := _zone(current_zone)
	if not here.is_empty() and int(here.get("type", 0)) == 2:
		_add_zone(current_zone)                              # in a dungeon: its own maps, nothing else
		return
	var cap := int(CAPITALS.get(realm, -1))
	if String(_zone(cap).get("map", "")) != "":
		_add_entry(String(_zone(cap).name).to_upper(), {"kind": "zone", "id": cap}, false)
		_pick.add_separator("")
		_entries.append({})
	var open: Array = []
	for k in (_maps.get("zones", {}) as Dictionary).keys():
		var z := _zone(int(k))
		if int(z.get("type", 0)) == 0 and int(z.get("region", -1)) in REALM_REGIONS.get(realm, []) and String(z.get("map", "")) != "":
			open.append(int(k))
	open.sort_custom(func(a, b): return String(_zone(a).name) < String(_zone(b).name))
	for z in open:
		_add_entry(String(_zone(z).name).to_upper(), {"kind": "zone", "id": z}, false)


func _add_zone(z: int) -> void:
	_add_entry(String(_zone(z).name).to_upper(), {"kind": "zone", "id": z}, false)
	var areas: Array = _zone(z).get("areas", [])
	for i in areas.size():
		var nm := String(areas[i].get("name", ""))
		_add_entry("   - " + (nm if nm != "" else "AREA %d" % (i + 1)).to_upper(), {"kind": "area", "id": z, "area": i}, false)


func _add_entry(text: String, what: Dictionary, header: bool) -> void:
	_pick.add_item(text)
	if header:
		_pick.set_item_tooltip(_pick.item_count - 1, "Realm map")
	_entries.append(what)


var _zone_npcs := {}                       # zone -> [[name, x, z], ...] its realm NPCs (from its npcs.json)
var _quest_cache := {}                     # zone -> [{at, kind}] (rebuilt when your quests / level change)
var _quest_key := []


## Quest marks for any zone (owner: see the quests you can take in a zone without being there). The current zone uses
## QuestMarkers' live marks; another zone reads its NPC list: yellow = a quest you can take now (your level / class /
## race / quests done), green = your step ends there, orange = its giver has your quest in progress.
func _zone_size_of(z: int) -> float:
	if z == current_zone:
		return zone_size
	var info := "res://content/zones/zone%03d/zone.json" % z
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(info)) if FileAccess.file_exists(info) else null
	return float((parsed as Dictionary).get("size_m", 1638.4)) if parsed is Dictionary else 1638.4


func zone_quest_marks(z: int) -> Array:
	if z == current_zone:
		return marks
	var key := [PlayerData.level, PlayerData.class_id()]   # a level / class change opens other quests
	if key != _quest_key:
		_quest_key = key
		_quest_cache.clear()
	if _quest_cache.has(z):
		return _quest_cache[z]
	var out := []
	var eng = get_tree().current_scene.get("quests") if get_tree() and get_tree().current_scene else null
	if eng == null:
		return out
	if not _zone_npcs.has(z):
		var list := []
		var path := "res://content/zones/zone%03d/npcs.json" % z
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if parsed is Dictionary:
			for sp in parsed.get("spawns", []):
				if int(sp.get("realm", 0)) != 0:
					list.append([String(sp.name), float(sp.pos[0]), float(sp.pos[2])])
		_zone_npcs[z] = list
	var targets := {}
	var givers := {}
	for id in PlayerData.quests:
		var st: Dictionary = eng.step_of(id)
		if String(st.get("target", "")) != "":
			targets[String(st.target).to_lower()] = true
		if String(st.get("custom", {}).get("target", "")) != "":
			targets[String(st.custom.target).to_lower()] = true
		givers[String(QuestDb.quest(id).get("giver", "")).to_lower()] = true
	var seen := {}
	for n in _zone_npcs[z]:
		var who := String(n[0])
		if seen.has(who):
			continue
		var kind := ""
		if targets.has(who.to_lower()):
			kind = "?"
		else:
			for q in QuestDb.by_giver(who):
				if eng.qualifies(q):
					kind = "!"
					break
			if kind == "" and givers.has(who.to_lower()):
				kind = "o"
		if kind != "":
			seen[who] = true
			out.append({"at": Vector2(n[1], n[2]), "kind": kind})
	_quest_cache[z] = out
	return out


func _on_quests_changed() -> void:
	_quest_cache.clear()


## Map space -> the region map square of zone z ([left, top, width, height] in the 256-px picture), or empty.
func region_square(r: int, z: int) -> Rect2:
	for p in _region(r).get("zones", []):
		if int(p.zone) == z:
			return Rect2(float(p.left), float(p.top), float(p.width), float(p.height))
	return Rect2()


class MapView extends Control:
	var window: MapWindow
	var texture: Texture2D
	var _hover := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	## The fraction (0..1 across the picture) of a spot given in the current zone's units, or (-1, -1) if not shown.
	func _frac(u: Vector2) -> Vector2:
		var w := window
		var s := w.shown
		var zunits := w.zone_size / 0.025
		match String(s.get("kind", "")):
			"zone":
				if int(s.id) != w.current_zone:
					return Vector2(-1, -1)
				var mr := w.map_rect(int(s.id))
				return (u - mr.position) / mr.size
			"area":
				if int(s.id) != w.current_zone:
					return Vector2(-1, -1)
				var r: Array = (w._zone(int(s.id)).areas as Array)[int(s.area)].rect
				var off := w.map_rect(int(s.id)).position
				return (u - off - Vector2(float(r[0]), float(r[1]))) / Vector2(float(r[2]), float(r[3]))
			"region":
				var sq := w.region_square(int(s.id), w.current_zone)
				if sq.size == Vector2.ZERO:
					return Vector2(-1, -1)
				return (sq.position + u / zunits * sq.size) / 256.0
		return Vector2(-1, -1)

	## A spot (in the SHOWN zone's units) on the shown zone / area map.
	func _mark_frac(u: Vector2) -> Vector2:
		var w := window
		var s := w.shown
		var mr := w.map_rect(int(s.id))
		if String(s.get("kind", "")) == "area":
			var r: Array = (w._zone(int(s.id)).areas as Array)[int(s.area)].rect
			return (u - mr.position - Vector2(float(r[0]), float(r[1]))) / Vector2(float(r[2]), float(r[3]))
		return (u - mr.position) / mr.size

	## Realm maps: each zone square with quests for you gets a yellow dot and their number (green / orange when only
	## turn-ins / quests in progress are there).
	func _draw_region_counts() -> void:
		var w := window
		for q in w._region(int(w.shown.id)).get("zones", []):
			var ms: Array = w.zone_quest_marks(int(q.zone))
			if ms.is_empty():
				continue
			var avail := ms.filter(func(m): return String(m.kind) == "!").size()
			var turn := ms.filter(func(m): return String(m.kind) == "?").size()
			var col := Color(1.0, 0.85, 0.15) if avail > 0 else (Color(0.3, 1.0, 0.35) if turn > 0 else Color(1.0, 0.55, 0.1))
			var n := avail if avail > 0 else (turn if turn > 0 else ms.size())
			var at := Vector2(float(q.left) + float(q.width) - 5.0, float(q.top) + 5.0) / 256.0 * size
			draw_circle(at, 6.5, Color(0.08, 0.05, 0.0))
			draw_circle(at, 5.5, col)
			var f := UiArt.font(true)
			var txt := str(n)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(f, at + Vector2(-tw * 0.5, 3.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.1, 0.06, 0.0))

	func _gui_input(event: InputEvent) -> void:
		var w := window
		if String(w.shown.get("kind", "")) != "region":
			return
		if event is InputEventMouseMotion:
			var z := _zone_under(event.position)
			if z != _hover:
				_hover = z
				tooltip_text = String(w._zone(z).get("name", "")) if z >= 0 else ""
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var z := _zone_under(event.position)
			if z >= 0 and String(w._zone(z).get("map", "")) != "":
				w._show({"kind": "zone", "id": z}, true)
				accept_event()

	func _zone_under(p: Vector2) -> int:
		var at := p / size * 256.0
		for q in window._region(int(window.shown.id)).get("zones", []):
			if Rect2(float(q.left), float(q.top), float(q.width), float(q.height)).has_point(at):
				return int(q.zone)
		return -1

	## The roadside inns (bot plan phase 6, owner: clearly labelled on their zone's map without covering what is
	## there): a gold marker, and the label on the quietest part of the painted map nearby (pipeline/place_inns.py
	## picked the spot), joined by a thin line.
	const SHOW_INNS := false
	static var _inns := {}

	func _draw_inns(zone_id: int) -> void:
		if _inns.is_empty():
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/inns.json"))
			_inns = (parsed as Dictionary).get("inns", {"-": {}}) if parsed is Dictionary else {"-": {}}
		for k in _inns:
			var inn: Dictionary = _inns[k]
			if inn.is_empty() or int(inn.get("zone", -1)) != zone_id:
				continue
			var lab: Dictionary = inn.get("map_label", {})
			var f := Vector2(float(inn.site[0]), float(inn.site[1])) / float(window._zone_size_of(zone_id))
			var at := f * size
			var off: Array = lab.get("offset", [0.02, -0.035])
			# owner 2026-10-11: like the map's own markers - small white text with a dark edge, no box, a small dot
			var font := UiArt.font(true)
			var fs := maxi(6, int(size.x / 44.0))
			var text := String(lab.get("text", "ROADSIDE INN"))
			var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			# beside the dot, on the side the quiet-spot pick chose (left / right, or above / below)
			var base := at + Vector2(5, tsize.y * 0.35)
			if float(off[0]) < -0.1:
				base.x = at.x - 5 - tsize.x
			elif float(off[0]) < 0.0:
				base = at + Vector2(-tsize.x * 0.5, (-6.0 if float(off[1]) < 0 else tsize.y + 4.0))
			draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0, 0, 0, 0.85))
			draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
			draw_circle(at, 2.6, Color(0, 0, 0, 0.85))
			draw_circle(at, 1.8, Color(1, 1, 1))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0))
		if texture:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
		var w := window
		if String(w.shown.get("kind", "")) == "region" and _hover >= 0:
			var sq := w.region_square(int(w.shown.id), _hover)
			draw_rect(Rect2(sq.position / 256.0 * size, sq.size / 256.0 * size), Color(1.0, 0.85, 0.3), false, 1.5)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.42, 0.35), false, 1.0)
		if String(w.shown.get("kind", "")) == "region":
			_draw_region_counts()
		else:
			for m in w.zone_quest_marks(int(w.shown.id)):   # quest marks for the shown zone, wherever you are
				var f := _mark_frac((m.at as Vector2) / 0.025)
				var mp := f * size
				if f.x < 0 or not Rect2(Vector2.ZERO, size).has_point(mp):
					continue
				# quest marks in the ground circles' colours: available yellow, turn-in green, in progress orange;
				# classic step markers / the emissary's hunt in red
				var col: Color = {"!": Color(1.0, 0.85, 0.15), "?": Color(0.3, 1.0, 0.35), "o": Color(1.0, 0.55, 0.1),
						"task": Color(0.8, 0.35, 1.0)}.get(
						String(m.kind), Color(0.95, 0.2, 0.15))
				draw_circle(mp, 3.5, Color(0.08, 0.05, 0.0))
				draw_circle(mp, 2.5, col)
			# your realm's gamebots and companions in this zone as green dots (bot plan phase 3, owner: also in
			# dungeons; enemy bots never; Options > BOTS > REALM BOTS ON MAP)
			if int(w.shown.get("id", -1)) == w.current_zone:
				for b in WorldLink.bot_dots():
					var bf := _mark_frac(Vector2(b.x, b.z) / 0.025)
					var bp := bf * size
					if bf.x < 0 or not Rect2(Vector2.ZERO, size).has_point(bp):
						continue
					draw_circle(bp, 2.8, Color(0.02, 0.08, 0.02))
					draw_circle(bp, 2.0, Color(0.3, 0.95, 0.3))
				# your companions in blue - their own colour (owner 2026-10-11: the orange looked like an in-progress quest
				# mark; blue is used for nothing else on the map)
				for c in WorldLink.companion_dots():
					var cf := _mark_frac(Vector2(c.x, c.z) / 0.025)
					var cpt := cf * size
					if cf.x < 0 or not Rect2(Vector2.ZERO, size).has_point(cpt):
						continue
					draw_circle(cpt, 3.0, Color(0.0, 0.03, 0.1))
					draw_circle(cpt, 2.2, Color8(70, 150, 255))
		# the roadside inns are shelved (owner 2026-10-11: 0.36c is the Claude version's world 1:1 - no inns on Avalon
		# Marsh / Myrkwood / Shannon Estuary); the drawing stays for if they come back ("INNS AND CUSTOM SYSTEMS (SHELVED).md")
		if SHOW_INNS and String(w.shown.get("kind", "")) == "zone":
			_draw_inns(int(w.shown.get("id", -1)))
		var p := w.player as Player
		if p == null:
			return
		var u := w._player_units()
		var f := _frac(Vector2(u.x, u.y))
		var at := f * size
		if f.x < 0 or not Rect2(Vector2.ZERO, size).has_point(at):
			return
		var fwd := Vector2(-sin(p.char_yaw), -cos(p.char_yaw))   # north up: forward -Z is up on the map
		var side := Vector2(-fwd.y, fwd.x)
		var tip := at + fwd * 7.0
		var pts := PackedVector2Array([tip, at - fwd * 4.0 + side * 4.5, at - fwd * 2.0, at - fwd * 4.0 - side * 4.5])
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.25))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.1, 0.05, 0.0), 1.0)
