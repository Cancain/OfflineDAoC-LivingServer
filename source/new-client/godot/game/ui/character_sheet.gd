class_name CharacterSheet
extends RefCounted
## The CHARACTER sheet of the right panel, on the client's charsheet.bmp (192x448; the captions are painted on the
## art, the values go in its boxes - coordinates measured on the bitmap, original pixels). Stats are the client's
## starting stats (PlayerData); the class's own three stats are drawn in the highlight colour as on the client's
## creation screen. Values the game doesn't compute yet (weapon skill, hit points ...) show "-"; nothing made up.

const STAT_ROWS := [158.0, 176.5, 194.5, 212.5]
const LEFT_STATS := ["STR", "CON", "DEX", "QUI"]
const RIGHT_STATS := ["INT", "EMP", "PIE", "CHA"]


static func build(parent: Control) -> void:
	var c := PlayerData.character
	_box(parent, Rect2(22, 47, 24, 14), str(PlayerData.level))
	_box(parent, Rect2(107, 47, 80, 14), str(PlayerData.realm_points))
	var lines := [["race", String(c.get("race", ""))], ["base", String(c.get("class_name", ""))],
			["profession", String(c.get("profession", ""))], ["title", String(c.get("title", ""))]]
	var srv: Dictionary = Server.info if Server.active else {}
	if not srv.is_empty():                                 # the server's own words (SendUpdatePlayer)
		lines = [["race", _word(srv.get("race_name", ""))], ["base", _word(srv.get("base_class", ""))],
				["profession", _word(srv.get("profession", ""))], ["title", _word(srv.get("title", ""))]]
	for i in lines.size():
		var l := UiArt.label(lines[i][1], 8, UiArt.CREAM)
		l.position = Vector2(64, 64 + i * 13)
		l.size = Vector2(122, 12)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		parent.add_child(l)
	# the server's numbers (owner 2026-10-14: "weapon skill, weapon damage, armor factor, hit points all that needs to
	# work"): SendUpdateWeaponAndArmorStats and the stats packet's hit points; "-" without a server
	var ws: Dictionary = Server.weapon_stats if Server.active else {}
	var hp := Server.max_hp if Server.active and Server.max_hp > 0 else int(srv.get("max_health", 0))
	_box(parent, Rect2(55, 117, 31, 15), str(int(ws.weapon_skill)) if ws.has("weapon_skill") else "-")   # weapon skill
	_box(parent, Rect2(156, 117, 31, 15), str(hp) if hp > 0 else "-")                                    # hit points
	_box(parent, Rect2(55, 135, 31, 14), "%.1f" % float(ws.weapon_damage) if ws.has("weapon_damage") else "-")
	_box(parent, Rect2(156, 135, 31, 14), str(int(ws.armor_factor)) if ws.has("armor_factor") else "-")   # armor factor
	# stats in the client's order STR CON DEX QUI | INT PIE EMP CHA; the sheet lists INT EMP PIE CHA on the right
	var right_index := [4, 6, 5, 7]
	for i in 4:
		for side in 2:
			var si: int = i if side == 0 else right_index[i]
			var now := int(PlayerData.effective_stats()[si]) if PlayerData.stats.size() == 8 else 0
			var norm := PlayerData.unmodified_stat(si)
			var v := str(now) if PlayerData.stats.size() == 8 else "-"
			var b := _box(parent, Rect2(5 if side == 0 else 95, STAT_ROWS[i], 24 if side == 0 else 25, 16), v)
			b.tooltip_text = (LEFT_STATS[i] if side == 0 else RIGHT_STATS[i])
			if Server.active and Server.stat_buffs.size() == 8 and PlayerData.stats.size() == 8:
				# the server's numbers (owner 2026-10-15: "con doesn't properly show up as red text after death ... negative
				# red and green values"): its buffs / debuffs part, and the constitution lost at deaths (CON = index 1)
				var buff := int(Server.stat_buffs[si])
				var lost := Server.con_lost if si == 1 else 0
				if buff < 0 or lost > 0:
					b.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
					b.tooltip_text += " %d (%s)" % [now, ", ".join(([] if buff >= 0 else ["DEBUFFED %d" % buff]) +
							([] if lost <= 0 else ["%d LOST AT DEATH" % lost]))]
				elif buff > 0:
					b.add_theme_color_override("font_color", Color(0.35, 1.0, 0.35))
					b.tooltip_text += " %d (BUFFED +%d)" % [now, buff]
				elif si in PlayerData.class_stats:
					b.add_theme_color_override("font_color", UiArt.GOLD_HI)
			elif PlayerData.stats.size() == 8 and now < norm:          # lowered (debuffs, constitution lost at death)
				b.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
				b.tooltip_text += " %d (NORMALLY %d)" % [now, norm]
			elif PlayerData.stats.size() == 8 and now > norm:        # raised by buffs
				b.add_theme_color_override("font_color", Color(0.35, 1.0, 0.35))
				b.tooltip_text += " %d (NORMALLY %d)" % [now, norm]
			elif si in PlayerData.class_stats:
				b.add_theme_color_override("font_color", UiArt.GOLD_HI)
	var info := RichTextLabel.new()
	info.position = Vector2(10, 258)
	info.size = Vector2(158, 148)
	info.bbcode_enabled = true
	info.scroll_active = true
	info.add_theme_font_override("normal_font", UiArt.font(true))
	info.add_theme_font_size_override("normal_font_size", 8)
	info.add_theme_color_override("default_color", UiArt.CREAM)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	UiArt.themed(info)
	var realm: String = {"alb": "ALBION", "mid": "MIDGARD", "hib": "HIBERNIA"}.get(String(c.get("realm", "")), "-")
	var weapon: String = {"standard": "STANDARD", "twohand": "TWO HANDED", "ranged": "RANGED"}.get(PlayerData.active_weapon, "-")
	var rows := [["REALM", realm]]
	if not srv.is_empty():
		# ADDITIONAL INFO: the rest of SendUpdatePlayer - realm rank (RealmLevel: rank * 10 + level, 1L0 first), its
		# title and the realm skill points, guild and rank, last name, crafting, master level, house - and the resists
		var rl := int(srv.get("realm_level", 0))
		rows.append(["REALM RANK", "%dL%d  %s" % [rl / 10 + 1, rl % 10, _word(srv.get("realm_title", ""))]])
		rows.append(["REALM SKILL POINTS", str(int(srv.get("realm_spec_points", 0)))])
		if _word(srv.get("guild", "")) != "":
			rows.append(["GUILD", (_word(srv.guild) + "  " + _word(srv.get("guild_title", ""))).strip_edges()])
		if _word(srv.get("last_name", "")) != "":
			rows.append(["LAST NAME", _word(srv.last_name)])
		if _word(srv.get("craft_skill", "")) != "":
			rows.append(["CRAFTING", (_word(srv.craft_skill) + "  " + _word(srv.get("craft_title", ""))).strip_edges()])
		if int(srv.get("ml_level", 0)) > 0:
			rows.append(["MASTER LEVEL", "%d  %s" % [int(srv.ml_level), _word(srv.get("ml_title", ""))]])
		if int(srv.get("house", 0)) > 0:
			rows.append(["HOUSE", "LOT %d" % int(srv.house)])
	rows.append(["ACTIVE WEAPON", weapon])
	rows.append(["MONEY", PlayerData.money_text().to_upper()])
	if Server.active and Server.resists.size() >= 9:
		var names := ["CRUSH", "SLASH", "THRUST", "HEAT", "COLD", "MATTER", "BODY", "SPIRIT", "ENERGY"]
		for i in 9:
			rows.append([names[i], "%d%%" % int(Server.resists[i])])
	var gold := UiArt.GOLD.to_html(false)
	info.text = "\n".join(rows.map(func(r): return "[color=#%s]%s[/color]  %s" % [gold, r[0], String(r[1]).to_upper()]))
	parent.add_child(info)


## A server text field: the server writes "None" for an empty one (NullOrEmptyToNone).
static func _word(v) -> String:
	var t := String(v)
	return "" if t == "None" else t


static func _box(parent: Control, r: Rect2, text: String) -> Label:
	var l := UiArt.label(text, 8, UiArt.CREAM)
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(l)
	return l
