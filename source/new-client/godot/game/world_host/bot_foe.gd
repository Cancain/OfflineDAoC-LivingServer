class_name BotFoe
extends RefCounted
## A gamebot in a zone's fights (bot plan phase 4): what the zone's monsters see - on their threat lists like you and
## your pets - and the bot's own character, a CharacterState (the same sheet and rules as the player's). The C# brain
## (BotSim) moves it and decides what to fight; Combat resolves the blows both ways with MeleeMath and leaves what
## happened in `events` for the brain (and the bot's log) to read.

var id := 0
var name := ""
var realm := ""                              # "alb" / "mid" / "hib"
var sheet: CharacterState
var pos := Vector3.ZERO
var yaw := 0.0                               # the player's convention (-Z ahead at 0)
var sitting := false
var moving := false
var alive := true
var last_result := ""                        # its own last swing: "hit" / "miss" / "style" / "evade" ...
var last_style := {}
var last_target: NpcState
var last_hit_at := -1e9                      # when it last swung or was swung at: "in combat" for 10 s (regeneration)
var tactics: Array = []                      # a companion's TACTICS bar: [{kind: "style" / "spell" / "ability", id}] by priority
var riding := false                          # on a route's mount (monsters leave riders alone)
var stance := "aggressive"                  # a companion's stance (Combat.companion_pick)
var prey: NpcState                           # what its brain is fighting (BotSim sets it; BotCaster casts at it)
var hold := 0.0                              # BotCaster: -1 stand still (casting), > 0 keep this range (m), 0 melee
var events: Array = []                       # {kind, ...} since the brain last looked
var _regen := 0.0
var _end_tick := 0.0


func setup(bot_id: int, record: Dictionary) -> void:
	id = bot_id
	name = String(record.get("name", "Bot"))
	realm = String(record.get("realm", "alb"))
	sheet = CharacterState.new()
	sheet.is_bot = true
	sheet.load_sheet(record)
	sheet.recalc_max()                                     # with the worn items' bonuses
	if not record.has("hp"):
		sheet.hp = sheet.max_hp
	alive = sheet.hp > 0
	sheet.message.connect(func(text: String, _kind: String): note("said", {"text": text}))


## Monsters it gave up on (a pull that never landed) and errands that failed, until when (seconds, engine clock).
var _skip := {}
var _blocked := {}
var hit_at := -1e9                           # when a monster last swung at it (an archer in melee takes its weapon)
var wants_buffs := false                     # BotCaster: a buff of its is missing (a companion casts it before it sits)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func skip_prey(st: NpcState, seconds: float) -> void:
	_skip[st] = _now() + seconds
	if _skip.size() > 64:
		for k in _skip.keys():
			if float(_skip[k]) < _now():
				_skip.erase(k)


func skipping(st: NpcState) -> bool:
	return _skip.has(st) and float(_skip[st]) > _now()


func block_errand(kind: String, seconds: float) -> void:
	_blocked[kind] = _now() + seconds


func errand_blocked(kind: String) -> bool:
	return _blocked.has(kind) and float(_blocked[kind]) > _now()


func level() -> int:
	return sheet.level


func note(kind: String, data: Dictionary = {}) -> void:
	data["kind"] = kind
	events.append(data)
	if events.size() > 64:
		events.pop_front()


## What happened since the last call (the brain reads it every think).
func take_events() -> Array:
	var e := events
	events = []
	return e


func in_combat() -> bool:
	return Time.get_ticks_msec() / 1000.0 - last_hit_at < 10.0


## The player's regeneration, the same rules (owner 2026-10-10: bots regenerate like players, /sit to rest - no fast
## rest): hit points and power every few seconds (sitting quicker, fighting slower), endurance every second.
func regen(delta: float) -> void:
	if not alive:
		return
	var fighting := in_combat()
	_regen += delta
	if _regen >= sheet.regen_interval(sitting, fighting):
		_regen = 0.0
		sheet.regen_tick()
	_end_tick += delta
	if _end_tick >= 1.0:
		_end_tick = 0.0
		sheet.endurance_tick(moving, sitting, fighting)


## Its record for saving (the sheet's numbers written back).
func record() -> Dictionary:
	sheet.store_sheet()
	return sheet.character


func free_sheet() -> void:
	if sheet:
		sheet.free()
		sheet = null
