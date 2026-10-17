class_name ClassDb
extends RefCounted
## Classes, specializations, spell lines, spells, styles and abilities (pipeline/build_classes.py, the old OfflineDAoC
## server's data). Rules written here, from that server's numbers:
##   spec points: levels 1-5 give their level each; later levels give class multiplier x level / 10
##   training a spec from n to n + 1 costs n + 1 points (a spec at level L has cost (L(L+1) - 2) / 2 in total)
##   autotrain: the class's autotrain specs rise for free to level / 4 (minimum 1)
##   specs with a negative "level acquired" are known from level 1 (the number only orders them)
##   "...Career" specs are hidden: they hand out the class's abilities by level

const DIR := "res://content/classes"

static var _classes := {}
static var _abilities_by_class := {}
static var _specs := {}
static var _lines := {}
static var _spells := {}
static var _styles := {}
static var _abilities := {}


static func _load() -> void:
	if not _classes.is_empty():
		return
	var c = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/classes.json"))
	_classes = c.get("classes", {}) if c is Dictionary else {}
	_abilities_by_class = c.get("abilities_by_class", {}) if c is Dictionary else {}
	var s = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/specs.json"))
	_specs = s.get("specs", {}) if s is Dictionary else {}
	_lines = s.get("lines", {}) if s is Dictionary else {}
	var sp = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/spells.json"))
	_spells = sp if sp is Dictionary else {}
	var st = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/styles.json"))
	_styles = st if st is Dictionary else {}
	var ab = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/abilities.json"))
	_abilities = ab if ab is Dictionary else {}


static func cls(id: int) -> Dictionary:
	_load()
	return _classes.get(str(id), {})


static func spec(key: String) -> Dictionary:
	_load()
	return _specs.get(key, {})


static func spell(id: int) -> Dictionary:
	_load()
	return _spells.get(str(id), {})


static func style(id: int) -> Dictionary:
	_load()
	return _styles.get(str(id), {})


static func ability(key: String) -> Dictionary:
	_load()
	return _abilities.get(key, {})


static func is_career(key: String) -> bool:
	return key.ends_with("Career")


## The specs a class has at a level: [{spec, level acquired}], careers included (callers skip them for display).
static func specs_at(class_id: int, level: int) -> Array:
	var out := []
	for e in cls(class_id).get("specs", []):
		if maxi(1, int(e.level)) <= level:
			out.append(e)
	return out


static func trainable_specs(class_id: int, level: int) -> Array:
	return specs_at(class_id, level).filter(func(e): return not is_career(String(e.spec)))


static func total_points(class_id: int, level: int) -> int:
	var mult := int(cls(class_id).get("spec_multiplier", 10))
	var pts := -1
	for i in range(1, level + 1):
		pts += i if i <= 5 else mult * i / 10
		if i > 40:
			pts += mult * (i - 1) / 20
	return maxi(pts, 0)


static func spec_cost_total(spec_level: int) -> int:
	return maxi(0, (spec_level * (spec_level + 1) - 2) / 2)


static func autotrain_level(class_id: int, key: String, char_level: int) -> int:
	if not (cls(class_id).get("autotrain", []) as Array).has(key):
		return 0
	return maxi(1, char_level / 4)


## Points spent on a set of spec levels, minus what autotrain gives for free.
static func points_used(class_id: int, char_level: int, specs: Dictionary) -> int:
	var used := 0
	for key in specs:
		var lvl := int(specs[key])
		used += spec_cost_total(lvl)
		var at := mini(autotrain_level(class_id, String(key), char_level), lvl)
		if at > 0:
			used -= spec_cost_total(at)
	return used


## Spell lines a class uses, each with the spells known at the given levels: a baseline line goes by character
## level, a specialization line by that spec's level.
static func spell_lines(class_id: int, char_level: int, specs: Dictionary) -> Array:
	_load()
	var mine := {}
	for e in specs_at(class_id, char_level):
		mine[String(e.spec)] = true
	var out := []
	for key in _lines:
		var l: Dictionary = _lines[key]
		if not mine.has(String(l.spec)):
			continue
		if int(l.get("class_hint", 0)) != 0 and int(l.class_hint) != class_id:
			continue
		var cap := char_level if bool(l.baseline) else int(specs.get(String(l.spec), 1))
		var known := []
		var levels := []                                  # (each spell's level in the line, by the same index)
		for e in l.spells:
			if int(e[1]) <= cap:
				known.append(int(e[0]))
				levels.append(int(e[1]))
		if not known.is_empty():
			out.append({"key": key, "name": l.name, "spec": l.spec, "baseline": l.baseline, "spells": known, "levels": levels})
	return out


## Combat styles known: the class's (or shared) styles of each spec at or under its trained level.
## Whether a specialization trains a spell line of its own (a magic spec, not a weapon or defence one).
static func spec_has_line(key: String) -> bool:
	_load()
	for k in _lines:
		var l: Dictionary = _lines[k]
		if String(l.spec) == key and not bool(l.baseline):
			return true
	return false


static func styles_known(class_id: int, specs: Dictionary) -> Array:
	_load()
	var out := []
	for id in _styles:
		var s: Dictionary = _styles[id]
		var cid := int(s.get("classid", 0))
		if cid != 0 and cid != class_id:
			continue
		var key := String(s.get("speckeyname", ""))
		if specs.has(key) and int(s.get("speclevelrequirement", 1)) <= int(specs[key]):
			out.append(s)
	out.sort_custom(func(a, b): return [a.speckeyname, int(a.speclevelrequirement)] < [b.speckeyname, int(b.speclevelrequirement)])
	return out


## Abilities a class has: SpecXAbility rows for its specs (careers included) at or under their levels.
static func abilities_known(class_id: int, char_level: int, specs: Dictionary) -> Array:
	_load()
	var have := {}
	for e in specs_at(class_id, char_level):
		var key := String(e.spec)
		have[key] = char_level if is_career(key) else int(specs.get(key, 1))
	var out := {}
	for cid in [str(class_id), "0"]:
		for r in _abilities_by_class.get(cid, []):
			if have.has(String(r.spec)) and int(r.spec_level) <= int(have[String(r.spec)]):
				var k := String(r.ability)
				out[k] = maxi(int(out.get(k, 0)), int(r.level))
	var list := []
	for k in out:
		list.append({"key": k, "level": out[k], "name": ability_name(k, int(out[k]))})
	return list


## An ability's name at a level, the client's way: "0|GenericArmor;1|Armor Ability: Cloth;..." picks the entry for
## the level, "%n" becomes the level ("Evade %n Ability" -> "Evade II Ability").
static func ability_name(key: String, lvl: int) -> String:
	var n := String(ability(key).get("name", key))
	if n.contains("|"):
		var pick := ""
		for part in n.split(";", false):
			var kv := part.split("|", true, 1)
			if kv.size() == 2 and int(kv[0]) <= lvl:
				pick = kv[1]
		n = pick if pick != "" else n
	return n.replace("%n", ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][clampi(lvl, 0, 10)]).strip_edges()


## A class id by its name ("Guardian", "Blademaster"), or 0.
static func by_name(name: String) -> int:
	_load()
	for k in _classes:
		if String(_classes[k].get("name", "")).to_lower() == name.to_lower() or String(_classes[k].get("key", "")).to_lower() == name.to_lower():
			return int(k)
	return 0


## The old server's GameTrainer.CanPromotePlayer: an advanced class, the player still its base class, level 5+, and a
## race the class takes.
static func can_promote(class_id: int, player_class: int, level: int, race: String) -> bool:
	var c := cls(class_id)
	if c.is_empty() or bool(c.get("is_base", false)) or int(c.get("base_class", 0)) != player_class or level < 5:
		return false
	var races: Array = c.get("races", [])
	return races.is_empty() or race == "" or races.any(func(r): return String(r).to_lower() == race.to_lower())


## A style by its in-game id (the "ID" column chains refer to), for a class (or shared), or {}.
static func style_by_game_id(game_id: int, class_id: int) -> Dictionary:
	_load()
	for k in _styles:
		var s: Dictionary = _styles[k]
		if int(s.get("id", 0)) == game_id and (int(s.get("classid", 0)) == class_id or int(s.get("classid", 0)) == 0):
			return s
	return {}


static var _spell_levels := {}


## The level a spell is learned at in its line (LineXSpell), for its chance to hit.
static func spell_level(spell_id: int) -> int:
	_load()
	if _spell_levels.is_empty():
		for key in _lines:
			for e in _lines[key].spells:
				_spell_levels[int(e[0])] = int(e[1])
	return int(_spell_levels.get(spell_id, 1))
