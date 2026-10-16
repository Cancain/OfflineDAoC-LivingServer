class_name CharacterStore
extends RefCounted
## Local characters, per account (no server): user://characters/<account>.json, a list of
##   {name, realm, prefix (fig3 figure: cel_m ...), race, gender, base (summary.txt key: CELT-ARMS ...), class_name,
##    look (Fig3Figure look), level, zone, town, created}
## 1.65 rules (owner 2026-10-09): characters are created as a BASE class and pick their advanced class at a trainer
## at level 5. Ten characters per realm, as on the client's select screen.

const DIR := "user://characters"
const SLOTS_PER_REALM := 10
const NAME_MIN := 3
const NAME_MAX := 20

static var selected := {}                    # the character PLAY took into the world (read by the zone viewer)


## Where a character enters the world: its saved start (the old server's table for its race + base class) when that
## zone is built, else Mag Mell in Lough Derg (the only town ready, owner 2026-10-09).
## {zone, zone_name, x, y, z (DAoC units, zone-local), heading} or the Mag Mell fallback
static func start_of(c: Dictionary) -> Dictionary:
	var st: Dictionary = c.get("start", {}) if c.get("start") is Dictionary else {}
	if not st.is_empty() and FileAccess.file_exists("res://content/zones/zone%03d/zone.json" % int(st.zone)):
		return st
	return {"zone": 200, "zone_name": "Lough Derg", "spot": "Mag Mell", "fallback": true}


static func _path(account: String) -> String:
	return "%s/%s.json" % [DIR, (account if account != "" else "local").to_lower()]


static func load_all(account: String) -> Array:
	var text := FileAccess.get_file_as_string(_path(account))
	var data = JSON.parse_string(text) if text != "" else null
	return data if data is Array else []


static func save_all(account: String, list: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(account), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(list, " "))
	return true


static func in_realm(account: String, realm: String) -> Array:
	return load_all(account).filter(func(c): return c.realm == realm)


## "" when the name can be used, else the reason shown to the player. Names are letters only, one word, the first
## letter capitalised (the client's rule), and unique on this account.
static func check_name(account: String, name: String) -> String:
	if name.length() < NAME_MIN or name.length() > NAME_MAX:
		return "Names are %d to %d letters." % [NAME_MIN, NAME_MAX]
	if RegEx.create_from_string("^[A-Za-z]+$").search(name) == null:
		return "Names use letters only."
	for c in load_all(account):
		if String(c.name).to_lower() == name.to_lower():
			return "You already have a character named %s." % c.name
	return ""


static func add(account: String, character: Dictionary) -> String:
	var err := check_name(account, String(character.name))
	if err != "":
		return err
	var list := load_all(account)
	if list.filter(func(c): return c.realm == character.realm).size() >= SLOTS_PER_REALM:
		return "This realm already has %d characters." % SLOTS_PER_REALM
	character["created"] = Time.get_datetime_string_from_system()
	list.append(character)
	return "" if save_all(account, list) else "Could not save the character."


static func update(account: String, character: Dictionary) -> void:
	var list := load_all(account)
	for i in list.size():
		if String(list[i].name) == String(character.name):
			list[i] = character
	save_all(account, list)


static func remove(account: String, name: String) -> void:
	save_all(account, load_all(account).filter(func(c): return String(c.name) != name))
