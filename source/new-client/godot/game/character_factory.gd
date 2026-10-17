class_name CharacterFactory
extends RefCounted
## A new character, the one way characters are made (character creation and the bots, bot plan phase 3 - one owner
## per rule): the realm's races and base classes (the client's character screens), which race / class pairs exist in
## 1.65 (pregame.json classes 'available'), the start location (the old server's StartupLocation table), a name from
## the client's race name syllables, and a random look within the race figure's options.

const PRE := "res://content/pregame/pregame.json"
const RACE_DIR := "res://content/characters/races"
const RACES := {
	"alb": [["Briton", "BRIT", "bri", "briton"], ["Avalonian", "AVAL", "ava", "avalon"], ["Highlander", "HIGH", "hig", "highlander"],
			["Saracen", "SARE", "sar", "saracen"], ["Inconnu", "INCO", "inc", "inconnu"]],
	"mid": [["Norse", "NORS", "nor", "viking"], ["Troll", "TROL", "tro", "troll"], ["Dwarf", "DWAR", "dwa", "dwarf"],
			["Kobold", "KOBO", "kob", "kobold"], ["Valkyn", "VALK", "val", "valkyn"]],
	"hib": [["Celt", "CELT", "cel", "celt"], ["Firbolg", "FIRB", "fir", "firbolg"], ["Elf", "ELF", "elf", "elf"],
			["Lurikeen", "LURI", "lur", "lurikeen"], ["Sylvan", "SYLV", "syl", "sylvan"]]}
const BASES := {"alb": ["FIGH", "ACOL", "MAGE", "ELEM", "ROGU", "ARAW"], "mid": ["WARR", "SPIR", "MYST", "NROG"],
				"hib": ["ARMS", "NATU", "MAGI", "STEA", "GROV"]}
const BASE_CLASS := {"FIGH": "Fighter", "ACOL": "Acolyte", "MAGE": "Mage", "ELEM": "Elementalist", "ROGU": "Rogue",
		"ARAW": "Disciple", "WARR": "Viking", "SPIR": "Seer", "MYST": "Mystic", "NROG": "Rogue", "ARMS": "Guardian",
		"NATU": "Naturalist", "MAGI": "Magician", "STEA": "Stalker", "GROV": "Forester"}

static var _meta := {}
static var _figures := {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PRE))
		_meta = parsed if parsed is Dictionary else {"classes": {}}
	return _meta


## Does this race / base class pair exist (and is it in this version)?
static func available(realm: String, race_i: int, base: String) -> bool:
	var info = meta().get("classes", {}).get("%s-%s" % [RACES[realm][race_i][1], base])
	return info != null and bool(info.get("available", true))


## A name from the client's syllable tables for the race (first + second + third part).
static func random_name(realm: String, race_i: int, rng: RandomNumberGenerator) -> String:
	var key: String = RACES[realm][race_i][3]
	var syl: Dictionary = meta().get("name_syllables", {})
	var name := ""
	for part in ["first", "second", "third"]:
		var opts: Array = syl.get("%s-%s" % [key, part], [])
		if opts.size() > 0:
			name += String(opts[rng.randi() % opts.size()])
	return name.capitalize().replace(" ", "")


static func figure_meta(prefix: String) -> Dictionary:
	if not _figures.has(prefix):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/figure.json" % [RACE_DIR, prefix]))
		_figures[prefix] = parsed if parsed is Dictionary else {}
	return _figures[prefix]


## A random look within the figure's options (the customize screen's RANDOMIZE).
static func random_look(prefix: String, rng: RandomNumberGenerator) -> Dictionary:
	var m := figure_meta(prefix)
	var look := {}
	for k in ["face", "eyes", "skin", "hair", "size", "tattoo"]:
		var n := Fig3Figure.option_count_of(m, look, k)
		if n > 0:
			look[k] = rng.randi() % n
	var hc := Fig3Figure.option_count_of(m, look, "hair_color")
	if hc > 0:
		look["hair_color"] = rng.randi() % hc
	var sliders := []
	for i in (m.get("sliders", []) as Array).size():
		sliders.append(rng.randi() % 9)
	look["sliders"] = sliders
	return look


## The character dictionary character creation saves (the same for players and bots).
static func make(realm: String, race_i: int, gender: int, base: String, name: String, look: Dictionary) -> Dictionary:
	var race: Array = RACES[realm][race_i]
	var start: Dictionary = meta().get("startup", {}).get("%s-%s" % [race[1], base], {})
	return {"name": name, "realm": realm, "prefix": "%s_%s" % [race[2], "m" if gender == 0 else "f"],
			"race": race[0], "gender": "male" if gender == 0 else "female", "base": "%s-%s" % [race[1], base],
			"class_name": BASE_CLASS[base], "look": look, "level": 1, "start": start}


## A level-1 character of a random race, gender and available base class in a realm, its name not in `taken`
## (lower-case names). Bots (phase 3) are made this way; the same seed gives the same character.
static func random_character(realm: String, seed: int, taken: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pairs := []
	for ri in (RACES[realm] as Array).size():
		for b in BASES[realm]:
			if available(realm, ri, b):
				pairs.append([ri, b])
	var pick: Array = pairs[rng.randi() % pairs.size()]
	var gender := rng.randi() % 2
	var name := ""
	for attempt in 50:
		name = random_name(realm, pick[0], rng)
		var ok_len := name.length() >= CharacterStore.NAME_MIN and name.length() <= CharacterStore.NAME_MAX
		if ok_len and not taken.has(name.to_lower()):
			break
	var prefix := "%s_%s" % [RACES[realm][pick[0]][2], "m" if gender == 0 else "f"]
	return make(realm, pick[0], gender, pick[1], name, random_look(prefix, rng))
