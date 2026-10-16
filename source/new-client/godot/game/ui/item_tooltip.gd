class_name ItemTooltip
extends RefCounted
## Hovering a weapon or armour piece: the client's mini delve box (owner's screenshots of the real client,
## 2026-10-09): the name in the item's con colour (its level against yours), then ItemDb.summary's lines
## ("Staff Weapon / Crush Damage / Dps: 16.5  Spd: 4.6 / Con: 100%  Dur: 100% / Qua: 96%  Bon: 35% / Two-Handed").
## Other items just show their name. The box itself is the tooltip panel (UiArt.tooltip_theme). Right-click opens
## the information window instead (GameUI.show_info).

# item cons as clear colours, like the client's item names (bright green, yellow) - grey / green / blue / yellow /
# orange / red / purple
const CON := {-3: Color8(170, 170, 170), -2: Color8(80, 220, 80), -1: Color8(90, 150, 255), 0: Color8(240, 230, 60),
		1: Color8(255, 150, 40), 2: Color8(255, 60, 60), 3: Color8(200, 110, 255)}

static var _con: Array = []


static func is_gear(it: Dictionary) -> bool:
	var ot := int(it.get("object_type", 0))
	return ot > 0 and ot <= ItemDb.SHIELD_TYPE


## A Control for _make_custom_tooltip, or null for the plain caption.
static func make(it: Dictionary) -> Control:
	if Server.active and (String(it.get("id", "")).begins_with("srv:") or it.has("detail_key")):
		# the server's delve text (hover: prefetched) - your slot's, or an exchange item's (its detail_key)
		var d := Server.item_lines(it.detail_key if it.has("detail_key") else int(String(it.id).substr(4)))
		if not d.is_empty():
			var sbox := VBoxContainer.new()
			sbox.add_theme_constant_override("separation", -1)
			sbox.add_child(_line(String(d.caption), con_color(int(it.get("level", 0)), PlayerData.level)))
			for l in d.lines:
				if String(l).strip_edges() != "":
					sbox.add_child(_line(String(l), UiArt.CREAM))
			return sbox
	if it.is_empty() or not is_gear(it):
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -1)
	box.add_child(_line(String(it.get("name", "")), con_color(int(it.get("level", 0)), PlayerData.level)))
	for l in ItemDb.summary(it):
		box.add_child(_line(l, UiArt.CREAM))
	return box


## The con step (-3 grey .. 3 purple) of an item / creature level against the player's.
static func con_value(item_level: int, player_level: int) -> int:
	if _con.is_empty():
		con_color(0, 1)
	var row: Array = _con[clampi(player_level, 0, _con.size() - 1)]
	return int(row[item_level]) if item_level >= 0 and item_level < row.size() else 3


static func con_color(item_level: int, player_level: int) -> Color:
	if _con.is_empty():
		# the con table (capnbry concolors, pipeline/build_npcs.py) - the same for every zone
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zone200/npcs.json"))
		_con = parsed.get("con", [[]]) if parsed is Dictionary else [[]]
	var row: Array = _con[clampi(player_level, 0, _con.size() - 1)]
	return CON.get(int(row[item_level]) if item_level >= 0 and item_level < row.size() else 3, Color.WHITE)


## A spell / style / ability's hover box (a quickbar slot, a magic / combat sheet row - owner 2026-10-14: "healing and
## damage details don't show up on hover"): the server's delve text (asked when the pointer reached it - not here yet:
## null, the plain name), or in the game's own world SkillInfo's lines.
static func skill(e: Dictionary) -> Control:
	if e.is_empty() or String(e.get("kind", "")) in ["item", "macro", "petcmd"]:
		return null
	if Server.active:
		var d := Server.skill_lines(e)
		return null if d.is_empty() else text_box(String(d.caption), d.lines)
	return text_box(String(e.get("name", "")), SkillInfo.lines(e))


## A caption over lines of text, the delve box's look.
static func text_box(caption: String, lines: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -1)
	box.add_child(_line(caption, UiArt.GOLD_HI))
	for l in lines:
		if String(l).strip_edges() != "":
			box.add_child(_line(String(l), UiArt.CREAM))
	return box


static func _line(text: String, col: Color) -> Label:
	var l := UiArt.label(text, 13, col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
