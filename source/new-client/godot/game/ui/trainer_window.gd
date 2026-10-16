class_name TrainerWindow
extends ClassicWindow
## The trainer's training window (training.bmp, 350x448: Specializations + Pts, then Realm Skills). Each spec shows
## its level and what the next level costs; clicking a spec selects it, TRAIN spends the points (PlayerData.train:
## n + 1 points from level n, never above the character level). Opened by right-clicking your own trainer.
## Realm Skills: the class's realm abilities as the server sends them (TrainerWindow code 1) - level, the next level's
## cost, greyed when its requirements aren't met; TRAIN on one sends the trainer's train request for the next level
## (owner 2026-10-13: the Sluaghbinder's 30 realm abilities, every class's).

const LIST := Rect2(10, 38, 322, 160)
const RA_LIST := Rect2(10, 244, 322, 162)
const ROW_H := 15.0
var _rows: VBoxContainer
var _ra_rows: VBoxContainer
var _points: Label
var _ra_points: Label
var _selected := ""
var _selected_ra := -1                        # a Realm Skills row (its place in the class's list)


func build() -> void:
	closable = true
	var scroll := ScrollContainer.new()
	scroll.position = LIST.position
	scroll.size = LIST.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size = Vector2(LIST.size.x - 8, 0)
	_rows.add_theme_constant_override("separation", 0)
	scroll.add_child(_rows)
	var ra_scroll := ScrollContainer.new()
	ra_scroll.position = RA_LIST.position
	ra_scroll.size = RA_LIST.size
	ra_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(ra_scroll)
	_ra_rows = VBoxContainer.new()
	_ra_rows.custom_minimum_size = Vector2(RA_LIST.size.x - 8, 0)
	_ra_rows.add_theme_constant_override("separation", 0)
	ra_scroll.add_child(_ra_rows)
	_ra_points = UiArt.label("", 9, UiArt.GOLD_HI)       # the box beside "Realm Skills": points to spend
	_ra_points.position = Vector2(156, 224)
	_ra_points.size = Vector2(50, 14)
	_ra_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_ra_points)
	_points = UiArt.label("", 9, UiArt.GOLD_HI)          # the box beside "Specializations", after its "Pts": the
	_points.position = Vector2(172, 20)                    # points to spend (owner 2026-10-14: it was empty, the
	_points.size = Vector2(34, 14)                         # number written again under the lists instead)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_points)
	var train := UiArt.button("TRAIN", Vector2(80, 18), 10)
	train.position = Vector2(254, 416)
	train.pressed.connect(func():
		if Server.active and _selected_ra >= 0:           # a realm ability: its next level
			for ra in Server.realm_abilities:
				if int(ra.index) == _selected_ra:
					Server.train_realm_ability(_selected_ra, int(ra.level) + 1)
			return
		if _selected == "":
			return
		if Server.active:                                  # the server trains: its train request by the window's place
			for sp in Server.trainer_specs:                # (PlayerTrainHandler), then the window again (new levels)
				if String(sp.name) == _selected:
					Server.client.call("TrainSpec", int(sp.index), int(sp.level) + 1)
					get_tree().create_timer(0.6).timeout.connect(func(): Server.client.call("TrainWindow"))
			return
		if PlayerData.train(_selected):
			refresh())
	add_child(train)
	PlayerData.hook(self, PlayerData.skills_changed, func():
		if visible:
			refresh())
	if Server.active:
		PlayerData.hook(self, Server.skills_changed, func():
			if visible:
				refresh())
		PlayerData.hook(self, Server.trainer_changed, func():
			if visible:
				refresh())


func open() -> void:
	refresh()
	show_window()


func refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	if Server.active:                                      # the trainer window's specializations (TrainerWindow 0)
		for sk in Server.trainer_specs:
			var key := String(sk.name)
			var lvl := int(sk.level)
			_rows.add_child(_row(key.to_upper(), str(lvl), "NEXT: %d" % (lvl + 1),
					UiArt.GOLD_HI if key == _selected else UiArt.CREAM, func():
						_selected = key
						_selected_ra = -1
						refresh()))
		_points.text = str(PlayerData.spec_points())
		_realm_rows()
		return
	for e in ClassDb.trainable_specs(PlayerData.class_id(), PlayerData.level):
		var key := String(e.spec)
		var lvl := int(PlayerData.specs.get(key, 1))
		var name := String(ClassDb.spec(key).get("name", key)).to_upper()
		_rows.add_child(_row(name, str(lvl), "NEXT: %d" % (lvl + 1), UiArt.GOLD_HI if key == _selected else UiArt.CREAM,
				func():
					_selected = key
					refresh()))
	_points.text = str(PlayerData.spec_points())


## One list row: the name, its level and the next level / cost in their own columns (the client's lists line up;
## spaces in the proportional font did not).
func _row(name: String, level: String, next: String, col: Color, pick: Callable) -> Button:
	var row := Button.new()
	row.flat = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(LIST.size.x - 10, ROW_H)
	row.pressed.connect(pick)
	for part in [[name, 2.0, 200.0, HORIZONTAL_ALIGNMENT_LEFT], [level, 196.0, 30.0, HORIZONTAL_ALIGNMENT_RIGHT],
			[next, 240.0, 70.0, HORIZONTAL_ALIGNMENT_LEFT]]:
		var l := UiArt.label(String(part[0]), 9, col)
		l.position = Vector2(float(part[1]), 0)
		l.size = Vector2(float(part[2]), ROW_H)
		l.horizontal_alignment = part[3]
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return row


## The Realm Skills list: name, level, the next level's cost; a realm ability whose requirements aren't met yet is
## greyed (the server bracketed its name).
func _realm_rows() -> void:
	for c in _ra_rows.get_children():
		c.queue_free()
	for ra in Server.realm_abilities:
		var idx := int(ra.index)
		var col := UiArt.GOLD_HI if idx == _selected_ra else (UiArt.CREAM if bool(ra.available) else Color(0.55, 0.55, 0.55))
		_ra_rows.add_child(_row(String(ra.name).to_upper(), str(int(ra.level)), "COST: %d" % int(ra.cost), col, func():
			_selected_ra = idx
			_selected = ""
			refresh()))
	_ra_points.text = str(Server.ra_points)
