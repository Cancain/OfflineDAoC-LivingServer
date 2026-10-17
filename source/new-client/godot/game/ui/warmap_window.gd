class_name WarMapWindow
extends ClassicWindow
## The realm war map (owner 2026-10-10; in-game it came with New Frontiers - "1.65 EXCEPTIONS MADE.txt"): the old
## OfflineDAoC client's classic-frontier version (pipeline/build_warmap.py). Tabs HIBERNIA / MIDGARD / ALBION (the
## client's page order), the realm's four frontier zone tiles at the client's XML positions, every keep on them in
## its owner's colour (map_icons.tga: grey none, green Hibernia, blue Midgard, red Albion; relic keeps their own
## icon), the realm symbol, UPDATE, and your own position when you stand in that frontier. Hover a keep for its name.

const DATA := "res://content/ui/warmap/warmap.json"
const BODY := Vector2(330, 416)                    # the client window's size
const OFFSET := Vector2(6, 20)                     # inside the stone frame (interact.bmp nine-patch)
const TABS := [["hib", "HIBERNIA"], ["mid", "MIDGARD"], ["alb", "ALBION"]]
const OWNER_NAME := {"none": "UNCLAIMED", "alb": "ALBION", "mid": "MIDGARD", "hib": "HIBERNIA"}

var data := {}
var realm := "alb"
var player: Node3D
var zone_id := -1
var _body: Control
var _tabs := {}
var _player_mark: TextureRect
var _icons_tex: Texture2D
# the server's game (owner 2026-10-14: keep sieges in the new client): the keeps as the server has them now -
# WarMapClaimedKeeps after a ShowWarmap request (opening the map, a tab, UPDATE): keep id -> {realm, claimed, guild,
# siege, teleport}; and who holds each relic (alb / mid / hib strength, then magic: the holder's realm, 0 none)
var live := {}
var relic_holders: Array = []
var fights: Array = []                       # WarMapDetailUpdate: [{zone, x, y (0..3 quarter of the zone), color, size, group}]
# map_icons.tga, the client's realmwar_key.xml templates: battles (crossed swords) large / medium / small rows, the
# colour by who fights (0 grey, 1 Albion-Midgard red-blue, 2 Albion-Hibernia red-green, 3 Midgard-Hibernia
# blue-green); groups ("scouting") by realm and size; the flames on a keep under siege
const BATTLE_ROW := {0: 64, 1: 48, 2: 32, 3: 32}
const BATTLE_COL := {0: 48, 1: 32, 2: 0, 3: 16}
const GROUP_ROW := {1: 32, 2: 48, 3: 64}
const GROUP_COL := {1: 96, 2: 80, 4: 64}                  # Albion grail, Midgard hammer, Hibernia tree
const FIGHT_NAMES := {0: "A BATTLE", 1: "ALBION AND MIDGARD FIGHT", 2: "ALBION AND HIBERNIA FIGHT", 3: "MIDGARD AND HIBERNIA FIGHT"}
const GROUP_NAMES := {1: "AN ALBION FORCE", 2: "A MIDGARD FORCE", 4: "A HIBERNIAN FORCE"}
const SERVER_PAGE := {"alb": 1, "mid": 2, "hib": 3}     # KeepManager.GetKeepsByRealmMap: keep id / 25 - 1
const REALM_KEY := {0: "none", 1: "alb", 2: "mid", 3: "hib"}
# relic temples -> their slot in the holders list
const RELIC_SLOT := {"excalibur": 0, "mjollner": 1, "lamfhota": 2, "myrddin": 3, "grallarhorn": 4, "dagda": 5}


func build() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	data = parsed if parsed is Dictionary else {}
	_icons_tex = _png("map_icons.png")
	realm = String(PlayerData.character.get("realm", "alb"))
	if not ["alb", "mid", "hib"].has(realm):
		realm = "alb"
	for i in TABS.size():
		var t := UiArt.button(TABS[i][1], Vector2(62, 15), 8)
		t.position = OFFSET + Vector2(15 + i * 64, 2)
		var key: String = TABS[i][0]
		t.pressed.connect(func(): show_realm(key))
		add_child(t)
		_tabs[key] = t
	var upd := UiArt.button("UPDATE", Vector2(62, 15), 8)
	upd.position = OFFSET + Vector2(254, 2)
	upd.tooltip_text = "REFRESH WHO HOLDS EACH KEEP"
	upd.pressed.connect(func(): show_realm(realm))
	visibility_changed.connect(func():
		if visible:
			_ask_server(realm))
	add_child(upd)
	_tabs["upd"] = upd
	show_realm(realm)


func show_realm(r: String) -> void:
	realm = r
	_ask_server(r)
	_draw_realm(r)


## The server's keeps for this page: page shown (code 0), then its keeps and fights (code 1).
func _ask_server(r: String) -> void:
	if not Server.active or Server.client == null or not visible:
		return
	Server.client.call("ShowWarmap", 0, int(SERVER_PAGE.get(r, 1)), 0)
	Server.client.call("ShowWarmap", 1, int(SERVER_PAGE.get(r, 1)), 0)


## WarMapClaimedKeeps / WarMapDetailUpdate (ServerWorld).
func server_update(kind: String, d: Dictionary) -> void:
	if kind == "warmap_fights":
		fights = d.get("fights", [])
		if visible:
			_draw_realm(realm)
		return
	if kind != "warmap_keeps":
		return
	for k in d.get("keeps", []):
		var id := (int(k.map) + 1) * 25 + int(k.index) + int(k.tower) * 256
		live[id] = k
	relic_holders = d.get("relics", [])
	if visible:
		_draw_realm(realm)


func _draw_realm(r: String) -> void:
	for k in _tabs:
		if k != "upd":
			(_tabs[k] as Button).add_theme_color_override("font_color", UiArt.GOLD_HI if k == r else UiArt.CREAM)
	if _body:
		_body.queue_free()
	_body = Control.new()
	_body.position = OFFSET
	_body.size = BODY
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	var page: Dictionary = data.get("pages", {}).get(r, {})
	if page.is_empty():
		return
	# each realm page has the client window's own size (Midgard 394 x 352, Albion / Hibernia 330 x 416)
	var body := Vector2(page.size[0], page.size[1]) if page.has("size") else BODY
	_body.size = body
	var want := body + Vector2(12, 42)
	min_size = want
	max_size = want
	set_window_size(want)
	if _tabs.has("upd"):
		(_tabs["upd"] as Control).position = OFFSET + Vector2(body.x - 76, 2)
	var tex := _png(String(page.texture))
	for t in page.tiles:
		var tile := TextureRect.new()
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(t.quad[0], t.quad[1], 128, 128)
		tile.texture = a
		tile.position = Vector2(t.pos[0], t.pos[1])
		tile.size = Vector2(128, 128)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(tile)
	if page.get("symbol"):
		var sym := TextureRect.new()
		var sa := AtlasTexture.new()
		sa.atlas = _png("realm_symb.png")
		sa.region = Rect2(page.symbol.quad[0], page.symbol.quad[1], 64, 64)
		sym.texture = sa
		sym.position = Vector2(page.symbol.pos[0], page.symbol.pos[1])
		sym.size = Vector2(64, 64)
		sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(sym)
	var held := {"alb": 0, "mid": 0, "hib": 0, "none": 0}
	var icons: Dictionary = data.get("icons", {})
	for k0 in page.keeps:
		var k: Dictionary = (k0 as Dictionary).duplicate()
		var lv: Dictionary = live.get(int(k.id), {})
		var extra := ""
		if not lv.is_empty():
			k["owner"] = REALM_KEY.get(int(lv.realm), "none")
			if bool(lv.claimed) and String(lv.guild) != "":
				extra += "\nCLAIMED BY %s" % String(lv.guild).to_upper()
			if bool(lv.siege):
				extra += "\nUNDER SIEGE"
		if String(k.kind) == "relic" and relic_holders.size() == 6:
			var slot := -1
			for word in RELIC_SLOT:
				if String(k.name).to_lower().contains(word):
					slot = int(RELIC_SLOT[word])
			if slot >= 0:
				var holder := int(relic_holders[slot])
				extra += "\nRELIC HELD BY %s" % (OWNER_NAME.get(REALM_KEY.get(holder, "none"), "-") if holder > 0 else "NO ONE (CARRIED)")
		if extra.contains("UNDER SIEGE"):                  # realmwar_siege: the flames (32 x 32) on the keep
			var fire := TextureRect.new()
			var fa := AtlasTexture.new()
			fa.atlas = _icons_tex
			fa.region = Rect2(96, 96, 32, 32)
			fire.texture = fa
			fire.position = Vector2(k.at[0], k.at[1]) - Vector2(16, 20)
			fire.size = Vector2(32, 32)
			fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_body.add_child(fire)
		var ic := TextureRect.new()
		var ia := AtlasTexture.new()
		ia.atlas = _icons_tex
		var src: Array = icons.get("relic", [96, 16]) if String(k.kind) == "relic" else icons.get("keep", {}).get(String(k.owner), [0, 16])
		ia.region = Rect2(src[0], src[1], 16, 16)
		ic.texture = ia
		ic.position = Vector2(k.at[0], k.at[1]) - Vector2(8, 8)       # the client: tile + offset - icon size / 2
		ic.size = Vector2(16, 16)
		ic.tooltip_text = "%s (LEVEL %d)\nHELD BY %s%s" % [String(k.name).to_upper(), int(k.level), OWNER_NAME.get(String(k.owner), "-"), extra]
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		_body.add_child(ic)
		held[String(k.owner)] = int(held.get(String(k.owner), 0)) + 1
	# battles and realm forces the server reports (WarMapMgr: a zone quarter each - 32 px of the zone's 128 px tile)
	var tile_at := {}
	for t in page.tiles:
		tile_at[int(t.get("zone", -1))] = Vector2(t.pos[0], t.pos[1])
	for f in fights:
		if not tile_at.has(int(f.zone)):
			continue
		var at: Vector2 = tile_at[int(f.zone)] + Vector2(int(f.x) * 32 + 16, int(f.y) * 32 + 16)
		var region := Rect2()
		var tip := ""
		if bool(f.group):
			var col := int(f.color)
			var sz := int(f.size)
			sz = maxi(maxi(sz & 3, (sz >> 2) & 3), (sz >> 4) & 3)   # (Albion type, Midgard type << 2, Hibernia << 4)
			if not GROUP_COL.has(col):
				continue
			region = Rect2(GROUP_COL[col], GROUP_ROW.get(clampi(sz, 1, 3), 48), 16, 16)
			tip = GROUP_NAMES.get(col, "A FORCE")
		else:
			region = Rect2(BATTLE_COL.get(int(f.color), 48), BATTLE_ROW.get(int(f.size), 48), 16, 16)
			tip = FIGHT_NAMES.get(int(f.color), "A BATTLE")
		var fi := TextureRect.new()
		var fa2 := AtlasTexture.new()
		fa2.atlas = _icons_tex
		fa2.region = region
		fi.texture = fa2
		fi.position = at - Vector2(8, 8)
		fi.size = Vector2(16, 16)
		fi.tooltip_text = tip
		fi.mouse_filter = Control.MOUSE_FILTER_STOP
		_body.add_child(fi)
	# the client's six text lines under the map: who holds this frontier's keeps
	var labels: Array = page.get("labels", [])
	var lines := ["%s FRONTIER" % OWNER_NAME[r], "ALBION HOLDS %d" % held.alb, "MIDGARD HOLDS %d" % held.mid,
			"HIBERNIA HOLDS %d" % held.hib]
	for i in mini(lines.size(), labels.size()):
		var l := UiArt.label(lines[i], 8, UiArt.GOLD_HI if i == 0 else UiArt.CREAM)
		l.position = Vector2(labels[i][0], labels[i][1])
		l.size = Vector2(120, 12)
		_body.add_child(l)
	_player_mark = TextureRect.new()
	var pa := AtlasTexture.new()
	pa.atlas = _icons_tex
	var pi: Array = icons.get("player", [99, 82, 11, 11])
	pa.region = Rect2(pi[0], pi[1], pi[2], pi[3])
	_player_mark.texture = pa
	_player_mark.size = Vector2(pi[2], pi[3])
	_player_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_mark.visible = false
	_body.add_child(_player_mark)


func _process(_delta: float) -> void:
	if not visible or _player_mark == null or player == null:
		return
	var page: Dictionary = data.get("pages", {}).get(realm, {})
	var shown := false
	for t in page.get("tiles", []):
		if int(t.zone) == zone_id:                         # (world - zone origin) / 512 px, in zone units
			var p := Vector2(player.global_position.x, player.global_position.z) / 0.025 / 512.0
			_player_mark.position = Vector2(t.pos[0], t.pos[1]) + p - _player_mark.size * 0.5
			shown = true
	_player_mark.visible = shown


func _png(file: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://content/ui/warmap/" + file))
	return ImageTexture.create_from_image(img) if img else null
