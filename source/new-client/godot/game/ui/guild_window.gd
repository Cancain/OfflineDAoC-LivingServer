class_name GuildWindow
extends ClassicWindow
## The guild window (owner 2026-10-17: "a high quality guild UI" for the server's gamebot guilds - a roster window
## chosen over pure 1.65, whose guild was only /gc who text). The server's social-window data (guild.cs
## SendSocialWindowData), asked for with "/gc who window <sort> <page> <show offline> [1 = alliance]": a header
## "TE,page,total,count" ("TA" the alliance tab) then up to ten members "E,pos,total,name,level,class id,rank,group,
## "zone or last on","note"" (the alliance: the guild in place of the note), as CT_SocialInterface lines
## (ServerWorld._social). GUILD / ALLIANCE tabs, sortable columns, ten a page, SHOW OFFLINE, and the selected member's
## actions as /gc commands - the server checks the rank's rights and answers in chat.

const BODY := Vector2(540, 318)
const ROWS := 10
const ROW_H := 16.0
const TOP := 64.0                                  # the column headers' row
# column: [key, header, x, width, [sort number listed A-Z / low-high, the other way]] - guild.cs eSocialWindowSort:
# a positive number lists the sorted column first to last, a negative one last to first
const COLS := [["name", "NAME", 14, 118, [1, -1]], ["level", "LVL", 134, 30, [2, -2]], ["class", "CLASS", 166, 92, [3, -3]],
		["rank", "RANK", 260, 38, [4, -4]], ["group", "GRP", 300, 30, [5, -5]],
		["zone", "ZONE / LAST ON", 332, 118, [6, -6]], ["note", "NOTE", 452, 76, [7, -7]]]
# the alliance tab has no rank column: the server shifts its sort numbers one column on (SendSocialWindowData -
# RANK sorts the group, GROUP the zone, and the guild only as GUILD_DESC 8 or ZONE_OR_ONLINE_ASC -6)
const ALLIANCE_COLS := [["name", "NAME", 14, 128, [1, -1]], ["level", "LVL", 144, 30, [2, -2]],
		["class", "CLASS", 176, 96, [3, -3]], ["group", "GRP", 274, 30, [4, -4]],
		["zone", "ZONE / LAST ON", 306, 120, [5, -5]], ["guild", "GUILD", 428, 100, [8, -6]]]

var tab := "guild"                                 # "guild" / "alliance"
var sort := 1                                      # the server's sort number
var page := 1
var show_offline := false
var total := 0
var members: Array = []                            # this page: [{pos, name, level, class, rank, group, zone, note|guild, online}]
var selected := ""
var typing: Callable                               # GameUI: open the chat line with a text (/send name ...)

var _title: Label
var _tabs := {}
var _offline: Button
var _offline_dot: TextureRect
var _headers: Control
var _rows: VBoxContainer
var _empty: Label
var _page_label: Label
var _prev: Button
var _next: Button
var _count: Label
var _actions := {}
var _pending: Array = []                           # the lines of the answer still coming in
var _asked_at := 0


func build() -> void:
	closable = true
	_title = UiArt.label("GUILD", 11, UiArt.GOLD_HI)
	_title.position = Vector2(12, 21)
	_title.size = Vector2(BODY.x - 24, 16)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.clip_text = true
	add_child(_title)
	var i := 0
	for t in [["guild", "GUILD"], ["alliance", "ALLIANCE"]]:
		var b := UiArt.button(t[1], Vector2(70, 15), 8)
		b.position = Vector2(14 + i * 72, 40)
		var key: String = t[0]
		b.pressed.connect(func():
			if tab != key:
				tab = key
				sort = 1
				page = 1
				selected = ""
				request())
		add_child(b)
		_tabs[key] = b
		i += 1
	# SHOW OFFLINE: the client's own radio button (radiobutton1.bmp: grey off, blue on) and its label
	_offline = Button.new()
	_offline.flat = true
	_offline.focus_mode = Control.FOCUS_NONE
	_offline.position = Vector2(160, 40)
	_offline.size = Vector2(96, 14)
	_offline.tooltip_text = "LIST MEMBERS WHO ARE NOT PLAYING TOO"
	_offline_dot = TextureRect.new()
	_offline_dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_offline_dot.size = Vector2(11, 11)
	_offline_dot.position = Vector2(0, 1)
	_offline_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offline.add_child(_offline_dot)
	var ol := UiArt.label("SHOW OFFLINE", 8, UiArt.CREAM)
	ol.position = Vector2(15, 1)
	ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offline.add_child(ol)
	_offline.pressed.connect(func():
		show_offline = not show_offline
		page = 1
		request())
	add_child(_offline)
	_count = UiArt.label("", 8, UiArt.DIM)
	_count.position = Vector2(300, 41)
	_count.size = Vector2(BODY.x - 314, 12)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_count)
	_headers = Control.new()
	_headers.position = Vector2(0, TOP)
	_headers.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_headers)
	var line := ColorRect.new()                          # a gold rule under the headers
	line.color = Color(UiArt.GOLD, 0.45)
	line.position = Vector2(12, TOP + 15)
	line.size = Vector2(BODY.x - 24, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	_rows = VBoxContainer.new()
	_rows.position = Vector2(12, TOP + 19)
	_rows.add_theme_constant_override("separation", 0)
	add_child(_rows)
	_empty = UiArt.label("", 9, UiArt.DIM)
	_empty.position = Vector2(12, TOP + 60)
	_empty.size = Vector2(BODY.x - 24, 14)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty)
	var foot := TOP + 22 + ROWS * ROW_H
	_prev = UiArt.button("<", Vector2(18, 15), 9)
	_prev.position = Vector2(14, foot)
	_prev.pressed.connect(func():
		if page > 1:
			page -= 1
			request())
	add_child(_prev)
	_page_label = UiArt.label("", 8, UiArt.CREAM)
	_page_label.position = Vector2(34, foot + 2)
	_page_label.size = Vector2(74, 12)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_page_label)
	_next = UiArt.button(">", Vector2(18, 15), 9)
	_next.position = Vector2(110, foot)
	_next.pressed.connect(func():
		if page * ROWS < total:
			page += 1
			request())
	add_child(_next)
	# the selected member's actions (the server says if your rank may: Guild.eRank Promote / Demote / Remove)
	var acts := [["send", "SEND", "SEND A PRIVATE MESSAGE"], ["invite", "INVITE", "INVITE TO YOUR GROUP"],
			["promote", "PROMOTE", "RAISE THEIR GUILD RANK BY ONE"], ["demote", "DEMOTE", "LOWER THEIR GUILD RANK BY ONE"],
			["remove", "REMOVE", "REMOVE FROM THE GUILD"]]
	var x := 140.0
	for a in acts:
		var b := UiArt.button(a[1], Vector2(56, 15), 8)
		b.position = Vector2(x, foot)
		b.tooltip_text = a[2]
		var key: String = a[0]
		b.pressed.connect(func(): _act(key))
		add_child(b)
		_actions[key] = b
		x += 58.0
	var bottom := foot + 20
	var extra := [["info", "GUILD INFO", "THE GUILD'S DETAILS IN CHAT (/GC INFO)"],
			["motd", "MOTD", "THE MESSAGE OF THE DAY IN CHAT (/GC MOTD)"],
			["refresh", "REFRESH", "ASK THE SERVER AGAIN"], ["leave", "LEAVE GUILD", "LEAVE YOUR GUILD (/GC QUIT)"]]
	x = 14.0
	for a in extra:
		var b := UiArt.button(a[1], Vector2(84 if a[0] != "refresh" else 64, 15), 8)
		b.position = Vector2(x if a[0] != "leave" else BODY.x - 98, bottom)
		b.tooltip_text = a[2]
		var key: String = a[0]
		b.pressed.connect(func(): _act(key))
		add_child(b)
		_actions[key] = b
		x += b.size.x + 2
	_rebuild()


func show_window() -> void:
	super.show_window()
	request()


## Ask the server for the page as it stands (the answer comes back as social lines: receive()).
func request() -> void:
	_rebuild()
	if not Server.active or _guild() == "":
		return
	_pending = []
	_asked_at = Time.get_ticks_msec()
	Server.command("/gc who window %d %d %d%s" % [sort, page, 1 if show_offline else 0, " 1" if tab == "alliance" else ""])
	get_tree().create_timer(1.6).timeout.connect(_rebuild, CONNECT_ONE_SHOT)   # "nobody online" when no answer came


## A social line for this window (ServerWorld._social): the header starts a page, the members follow.
func receive(fields: Array) -> void:
	var kind := String(fields[0])
	if kind == "TE" or kind == "TA":
		page = maxi(1, int(fields[1]) if fields.size() > 1 else 1)
		total = int(fields[2]) if fields.size() > 2 else 0
		_pending = []
		if total == 0 or (fields.size() > 3 and int(fields[3]) == 0):
			members = []
			_rebuild()
		return
	if fields.size() < 10:
		return
	# GuildMemberView.ToString: both tabs the same fields, the alliance's last one its guild in place of the note
	var m := {"pos": int(fields[1]), "name": String(fields[3]), "level": int(fields[4]),
			"class": Server.class_name_of(int(fields[5])), "rank": int(fields[6]), "group": int(fields[7]),
			"zone": String(fields[8])}
	m["note" if kind == "E" else "guild"] = String(fields[9])
	total = int(fields[2])
	m["online"] = int(m.group) > 0                       # (the group size: 0 offline, 1 alone, 2 grouped)
	_pending.append(m)
	members = _pending.duplicate()
	_rebuild()


func _guild() -> String:
	return String(Server.info.get("guild", "")).strip_edges() if Server.active else ""


func _cols() -> Array:
	return COLS if tab == "guild" else ALLIANCE_COLS


func _rebuild() -> void:
	if _rows == null:
		return
	var g := _guild()
	_title.text = ("GUILD - " + g.to_upper()) if g != "" else "GUILD"
	_offline_dot.texture = UiArt.region("radiobutton1", Rect2(16 if show_offline else 0, 0, 16, 16))
	for k in _tabs:
		(_tabs[k] as Button).add_theme_color_override("font_color", UiArt.GOLD_HI if k == tab else UiArt.CREAM)
	for c in _headers.get_children():
		c.queue_free()
	for col in _cols():
		var h := Button.new()
		var pair: Array = col[4]
		var mark := "  ^" if sort == int(pair[0]) else ("  v" if sort == int(pair[1]) else "")
		h.text = String(col[1]) + mark
		h.flat = true
		h.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.position = Vector2(col[2], 0)
		h.size = Vector2(col[3], 14)
		h.focus_mode = Control.FOCUS_NONE
		h.add_theme_font_override("font", UiArt.font(true))
		h.add_theme_font_size_override("font_size", 8)
		h.add_theme_color_override("font_color", UiArt.GOLD)
		h.add_theme_color_override("font_hover_color", UiArt.GOLD_HI)
		h.tooltip_text = "SORT BY " + String(col[1])
		h.pressed.connect(func():                       # the same column again: the other way round
			sort = int(pair[1]) if sort == int(pair[0]) else int(pair[0])
			page = 1
			request())
		_headers.add_child(h)
	for c in _rows.get_children():
		c.queue_free()
	for m in members:
		_rows.add_child(_row(m))
	var pages := maxi(1, ceili(total / float(ROWS)))
	_page_label.text = "PAGE %d / %d" % [mini(page, pages), pages]
	_prev.disabled = page <= 1
	_next.disabled = page >= pages
	_count.text = ("%d MEMBERS" % total) if total > 0 else ""
	if not Server.active:
		_empty.text = "THE GUILD WINDOW NEEDS THE SERVER'S GAME"
	elif g == "":
		_empty.text = "YOU ARE NOT IN A GUILD"
	elif members.is_empty():
		_empty.text = "NO ALLIANCE" if tab == "alliance" and total == 0 and Time.get_ticks_msec() - _asked_at > 1500 \
				else ("NOBODY ONLINE - TICK SHOW OFFLINE" if not show_offline and Time.get_ticks_msec() - _asked_at > 1500 else "")
	else:
		_empty.text = ""
	_empty.visible = members.is_empty()
	var has := selected != "" and members.any(func(m): return m.name == selected)
	for k in ["send", "invite", "promote", "demote", "remove"]:
		(_actions[k] as Button).disabled = not has or (tab == "alliance" and k in ["promote", "demote", "remove"])
	for k in ["info", "motd", "leave"]:
		(_actions[k] as Button).disabled = g == ""


## One member: online ones bright, offline dim; the group column a dot when grouped; click to select, double-click
## to send them a message.
func _row(m: Dictionary) -> Control:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(BODY.x - 24, ROW_H)
	var sel: bool = m.name == selected
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UiArt.GOLD, 0.22) if sel else (Color(1, 1, 1, 0.035) if int(m.pos) % 2 == 0 else Color(0, 0, 0, 0))
	row.add_theme_stylebox_override("normal", bg)
	var hov := bg.duplicate() as StyleBoxFlat
	hov.bg_color = Color(UiArt.GOLD, 0.30 if sel else 0.12)
	row.add_theme_stylebox_override("hover", hov)
	row.add_theme_stylebox_override("pressed", hov)
	row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var color: Color = UiArt.GOLD_HI if sel else (UiArt.CREAM if bool(m.online) else UiArt.DIM)
	for col in _cols():
		var key: String = col[0]
		var text := ""
		match key:
			"name": text = String(m.name)
			"level": text = str(int(m.level))
			"class": text = String(m["class"])
			"rank": text = ("LEADER" if int(m.get("rank", 9)) == 0 else str(int(m.get("rank", 9))))
			"group": text = ("GRP" if int(m.group) > 1 else "") if bool(m.online) else ""
			"zone": text = String(m.zone)
			"note": text = String(m.get("note", ""))
			"guild": text = String(m.get("guild", ""))
		var l := UiArt.label(text.to_upper(), 8, color if key != "group" else UiArt.GREEN)
		l.position = Vector2(int(col[2]) - 12 + 2, 2)
		l.size = Vector2(int(col[3]) - 4, 12)
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if key in ["zone", "note", "guild"] and text != "":
			row.tooltip_text = (row.tooltip_text + "\n" if row.tooltip_text != "" else "") + text
		row.add_child(l)
	var nm := String(m.name)
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			selected = nm
			if e.double_click:
				_act("send")
			_rebuild())
	return row


func _member(name: String) -> Dictionary:
	for m in members:
		if m.name == name:
			return m
	return {}


func _act(key: String) -> void:
	if not Server.active:
		return
	var m := _member(selected)
	match key:
		"send":
			if not m.is_empty() and typing.is_valid():
				typing.call("/send %s " % m.name)
		"invite":
			if not m.is_empty():
				Server.command("/invite %s" % m.name)
		"promote", "demote":                             # one rank up (0 = leader) or down; the server checks rights
			if not m.is_empty():
				var r := int(m.get("rank", 9))
				var to := r - 1 if key == "promote" else r + 1
				if to < 0 or to > 9:
					PlayerData.message.emit("%s cannot be %s any further." % [m.name, key + "d"], "system")
					return
				Server.command("/gc %s %s %d" % [key, m.name, to])
				_refresh_soon()
		"remove":
			if not m.is_empty():
				var who := String(m.name)
				UiArt.confirm(get_parent(), "REMOVE MEMBER", "Remove %s from the guild?" % who, "REMOVE", "CANCEL",
						func(): Server.command("/gc remove %s" % who); _refresh_soon())
		"info":
			Server.command("/gc info")
		"motd":
			Server.command("/gc motd")
		"refresh":
			request()
		"leave":
			UiArt.confirm(get_parent(), "LEAVE GUILD", "Leave %s?" % _guild(), "LEAVE", "CANCEL",
					func(): Server.command("/gc quit"); _refresh_soon())


func _refresh_soon() -> void:
	get_tree().create_timer(0.8).timeout.connect(func():
		if visible:
			request(), CONNECT_ONE_SHOT)
