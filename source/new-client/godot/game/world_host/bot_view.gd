class_name BotView
extends Node3D
## A gamebot (or companion) drawn in the game (bot plan phase 3): its race figure with its look and worn gear (the
## same Player.dress the player and the select screen use), its nameplate, and a click box. GameBots (C#) moves it to
## the bot's body every frame and tells it the bot's state (run / idle / sit) when that changes.
## Nameplates (owner 2026-10-10, from the owner's old-client screenshots): your group orange; your realm, not grouped,
## periwinkle blue; another realm red, shown as race + realm rank title instead of the name; bright white when clicked;
## within the NPC name range. Options > INTERFACE > BOTS hides companions' and / or gamebots' names (both on by default).
## Drawing cost (owner 2026-10-11: 65 bots in Connla took the game from 130-140 to 50-60 fps): the NPCs' rules - AnimLod
## (animation by distance and screen, the shared skeleton budget, no shadow far away) - and no per-bot _process: one
## BotViewTicker steps every figure, the near ones every frame, farther ones every 2nd / 4th with the time gathered.

const GROUP := Color8(240, 168, 80)
const FRIENDLY := Color8(158, 154, 220)
const ENEMY := Color8(215, 64, 56)
const TARGETED := Color.WHITE
const OUTLINE := Color(0.02, 0.04, 0.02, 0.9)
const NAME_RANGE := NamePlates.NAME_RANGE     # the NPC name range (NamePlates)
const EM := 0.018
const RR1_TITLE := {"alb": "Guardian", "mid": "Skiltvakten", "hib": "Savant"}   # realm rank 1 (no realm points yet)
const PICK_LAYER := 1 << 10

static var views: Array = []                 # every BotView in the tree (BotViewTicker steps them)
static var _opts_at := -1.0
static var _opts := {}

var record: Dictionary = {}
var bot_id := 0
var companion := false
var grouped := false
var targeted := false
var figure: Fig3Figure
var _labels: Array = []
var _state := ""
var _size := -1
var _lod: AnimLod
var sounds: CharacterSounds                  # its voice (CharacterSounds - the race's creature sheet)
const WEAPONLESS := 19                       # cc_weapons row for bare-handed blows (Combat.WEAPONLESS)
var _weapons: Array = []                     # the weapon models Player.dress hung on it (freed on the next redress)
var pending := 0.0                           # time gathered since its last tick (BotViewTicker)


## Options > INTERFACE > BOTS: "names_gamebots", "names_companions", "map_dots" (all on by default).
static func option(key: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _opts_at > 1.0:
		_opts_at = now
		var cfg := ConfigFile.new()
		cfg.load(UiArt.settings_path)
		for k in ["names_gamebots", "names_companions", "map_dots"]:
			_opts[k] = bool(cfg.get_value("bots", k, true))
	return bool(_opts.get(key, true))


func setup(rec: Dictionary) -> void:
	record = rec
	bot_id = int((rec.get("bot", {}) as Dictionary).get("id", 0))
	name = "Bot%d" % bot_id
	figure = Fig3Figure.new()
	add_child(figure)
	if figure.load_figure(String(rec.get("prefix", "cel_m"))):
		figure.apply(rec.get("look", {}))
	_lod = AnimLod.new(self, figure, figure.anim)
	var sound_set := int(figure.meta.get("sound_set", 0))
	if sound_set > 0 and figure.anim:                     # its race's voice: swings, pain, evades, death
		sounds = CharacterSounds.new()
		sounds.name = "Sounds"
		add_child(sounds)
		AnimLod.keep_on_main(sounds)
		sounds.setup(figure, figure.anim, sound_set, false)
	if AnimLod.threaded:                                  # steps itself on a worker thread; the plate is the ticker's
		_phase = int(get_instance_id() % 4)
		AnimLod.run_threaded(self)
		set_process(true)
	else:
		set_process(false)
	redress(rec)
	_build_plate()
	var body := StaticBody3D.new()
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("bot", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 2.0, 0.7)             # a person's drawn box, as the NPC click boxes (Npc._build_pick)
	shape.shape = box
	shape.position.y = 1.0
	body.add_child(shape)
	add_child(body)
	set_state("idle")


## Its worn gear and weapons on the figure (again after a companion is handed something - Companions).
func redress(rec: Dictionary) -> void:
	record = rec
	var inv: Dictionary = rec.get("inventory", {}) if rec.get("inventory") is Dictionary else {}
	var item_at := func(slot: int) -> Dictionary:
		var e = inv.get(str(slot))
		if not (e is Dictionary):
			e = inv.get(slot)
		return ItemDb.item(String(e.id)) if e is Dictionary and e.has("id") else {}
	for w_ in _weapons:                                    # the weapons it held before (a staff taken back stayed in its
		if is_instance_valid(w_):                          # hand - owner 2026-10-11)
			(w_ as Node).queue_free()
	_weapons = Player.dress(figure, item_at, String(rec.get("active_weapon", "standard")), _drawn)
	var w: Dictionary = item_at.call({"standard": 10, "twohand": 12, "ranged": 13}.get(String(rec.get("active_weapon", "standard")), 10))
	_stance = WeaponModels.stance(int(w.get("model", 0))) if not w.is_empty() else ""
	_ranged = WeaponModels.ranged_kind(int(item_at.call(13).get("model", 0)))
	if _lod:
		_lod.refresh_shadow()                              # (new gear pieces take its shadow setting)


## Its weapons out of the sheath for a fight and back after it (owner 2026-10-11: gamebots swung empty hands - the
## figure kept the sheathed hang it was dressed with), as the player's attack mode does. Weapons only (GameBots).
func set_drawn(on: bool) -> void:
	if on == _drawn or figure == null:
		return
	_drawn = on
	var inv: Dictionary = record.get("inventory", {}) if record.get("inventory") is Dictionary else {}
	var item_at := func(slot: int) -> Dictionary:
		var e = inv.get(str(slot))
		if not (e is Dictionary):
			e = inv.get(slot)
		return ItemDb.item(String(e.id)) if e is Dictionary and e.has("id") else {}
	for w_ in _weapons:
		if is_instance_valid(w_):
			(w_ as Node).queue_free()
	_weapons = Player.dress(figure, item_at, String(record.get("active_weapon", "standard")), _drawn, false)
	if _lod:
		_lod.refresh_shadow()


func set_state(s: String) -> void:
	if s == _state or figure == null:
		return
	var was := _state
	_state = s
	if _casting and (s == "run" or s == "dead"):            # a cast can't go on through a run or a death (no signal comes)
		_casting = false
		SpellFx.drop(_gather)
		_gather = []
	if s == "dead" and was != "dead" and sounds:
		sounds.event("die")
	if s == "dead":
		figure.play("death")                               # played once; the last frame holds (a clamp clip)
		return
	if s == "sit" and was != "sit" and figure.anim and figure.anim.has_animation("sit_down"):
		_one_shot("sit_down")                              # down, then the sitting loop
		return
	if _action_left <= 0.0:
		figure.play(_cast_clips[1] if _casting and figure.anim and figure.anim.has_animation(_cast_clips[1]) else _loop_clip(s))


## The looping clip of a state: run / idle / sitting / the fighting stance (combat_idle for the weapon's stance).
func _loop_clip(s: String) -> String:
	if s.begins_with("ride:"):                          # on a route's mount: the route's rider clip
		var clip := s.trim_prefix("ride:")
		return clip if figure.anim and figure.anim.has_animation(clip) else "idle"
	match s:
		"run": return "run"
		"sit": return "sit_idle"
		"fight":
			return WeaponModels.stance_clip(figure.anim, _stance, "combat_idle")
	return "idle"


var _drawn := false                           # weapons in hand (fighting) or sheathed on belt / back (Player.dress)
var _stance := ""                             # the weapon's stance (WeaponModels.STANCES)
var _ranged := "bow"                          # its ranged weapon's clips: bow / xbow / throw
var _action_left := 0.0                       # a one-shot clip playing (swing, flinch, defence)


## One swing (the player's clips: a random high / medium / low attack for the weapon's stance).
## The weapon in hand's sound set (objects.csv via WeaponModels), 0 bare-handed.
func weapon_set() -> int:
	var inv: Dictionary = record.get("inventory", {}) if record.get("inventory") is Dictionary else {}
	var slot := {"standard": 10, "twohand": 12, "ranged": 13}.get(String(record.get("active_weapon", "standard")), 10) as int
	var e = inv.get(str(slot))
	if not (e is Dictionary):
		e = inv.get(slot)
	if not (e is Dictionary) or not e.has("id"):
		return 0
	return int(WeaponModels.info(int(ItemDb.item(String(e.id)).get("model", 0))).get("sound_set", 0))


func swing() -> void:
	if sounds:
		var ws := weapon_set()
		if ws > 0:
			sounds.weapon(ws, "use")
		else:
			sounds.event("attack")
	_one_shot(WeaponModels.attack_clip(figure.anim, _stance))


func flinch() -> void:
	if sounds and _state != "dead":
		sounds.event("pain_light")
	if _action_left <= 0.0 and _state != "dead":
		_one_shot("flinch")


func defend(kind: String) -> void:
	if sounds and _state != "dead":
		if kind == "evade":
			sounds.event("evade")
		else:
			sounds.weapon(WEAPONLESS, "parried" if kind == "parry" else "blocked")
	if _action_left > 0.0 or _state == "dead":
		return
	var clip := WeaponModels.defend_clip(figure.anim if figure else null, _stance, kind)
	if clip != "":
		_one_shot(clip)


var _gather: Array = []                      # the hand glows of the spell it is casting (SpellFx.begin)
var _cast_clips := ["cast_start", "cast_mid", "cast_end"]
var _casting := false                          # between cast_begin and its fire / fizzle: the casting loop plays


## A spell begins (BotCaster -> BotSim "cast:<effect>"): the spell's own casting style, as the player's cast_start.
func cast_begin(effect: int) -> void:
	if _state == "dead":
		return
	_casting = true
	_cast_clips = ["cast_start", "cast_mid", "cast_end"]
	var clips: Array = SpellFx.effect(effect).get("anims", [])
	for i in mini(clips.size(), 3):
		if String(clips[i]) != "" and figure.anim and figure.anim.has_animation(String(clips[i])):
			_cast_clips[i] = String(clips[i])
	SpellFx.drop(_gather)
	_gather = SpellFx.begin(effect, self, sounds)
	_one_shot(_cast_clips[0])


## ...it goes off: the cast effects and sound, the closing clip.
func cast_fire(effect: int) -> void:
	_casting = false
	SpellFx.fire(effect, _gather, self, sounds)
	if _state != "dead":
		_one_shot(_cast_clips[2])


## ...a spell landed on it (a buff, a heal): the effect on its body, as on you (SpellFx.land - the bone shield round
## a Bonedancer, a heal's glow).
func cast_land(effect: int) -> void:
	if _state != "dead":
		SpellFx.land(effect, self, 1.8, sounds)


## ...it is spoilt.
func cast_fizzle(effect: int) -> void:
	_casting = false
	SpellFx.fizzle(effect, _gather, sounds)
	_action_left = 0.0
	if figure and _state != "dead":
		figure.play(_loop_clip(_state))


## The bow: drawing, then the shot (the player's bow_draw / bow_release clips).
func bow(stage: String) -> void:
	if _state == "dead":
		return
	if stage == "draw":
		_one_shot(_ranged + "_aim" if figure.anim and figure.anim.has_animation(_ranged + "_aim") else _ranged + "_ready")
	else:
		_one_shot(_ranged + "_fire")


func _one_shot(clip: String) -> void:
	if figure == null or figure.anim == null or not figure.anim.has_animation(clip):
		return
	figure.anim.play(clip, 0.1)
	figure.anim.seek(0.0, true)
	_action_left = figure.anim.get_animation(clip).length
	if _lod:
		_lod.pose_now()


func display_name() -> String:
	if _enemy():
		return "%s %s" % [String(record.get("race", "")), RR1_TITLE.get(String(record.get("realm", "")), "")]
	return String(record.get("name", ""))


func _enemy() -> bool:
	return String(record.get("realm", "")) != PlayerData.realm_key()


func _build_plate() -> void:
	var guild := String(record.get("guild", ""))
	for text in ([display_name()] + (["<%s>" % guild] if guild != "" and not _enemy() else [])):
		var l := Label3D.new()
		l.text = text
		l.font = UiArt.font(true)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.shaded = false
		l.double_sided = true
		l.outline_modulate = OUTLINE
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.position = Vector3(0, 1.85 * (figure.scale.y if figure else 1.0) + 0.2, 0)
		add_child(l)
		_labels.append(l)


func _enter_tree() -> void:
	views.append(self)


func _exit_tree() -> void:
	views.erase(self)


func lod_dist() -> float:
	return _lod.last_dist if _lod else 0.0


var _phase := 0


## Threaded posing (AnimLod.threaded): near ones every frame, farther every 2nd / 4th with the time gathered.
func _process(delta: float) -> void:
	pending += delta
	var d := lod_dist()
	var stride := 1 if AnimLod.FULL or Perf.brute or d < AnimLod.NEAR_FULL_M else (2 if d < 45.0 else 4)
	if (Engine.get_process_frames() + _phase) % stride != 0:
		return
	_anim_step(pending, null)
	pending = 0.0


func _anim_step(delta: float, cam: Camera3D) -> void:
	if _action_left > 0.0:
		_action_left -= delta
		if _action_left <= 0.0 and _state != "dead" and figure:
			if _casting and figure.anim and figure.anim.has_animation(_cast_clips[1]):
				figure.play(_cast_clips[1])                    # the casting loop until the spell goes off
			else:
				figure.play(_loop_clip(_state))
	if _lod:
		_lod.step(delta, cam)


## One step (BotViewTicker, main thread): the animation too when posing isn't threaded, and the nameplate.
func tick(delta: float, cam: Camera3D, player_pos: Vector3) -> void:
	if not AnimLod.threaded:
		_anim_step(delta, cam)
	plate(cam, player_pos)


func plate(cam: Camera3D, player_pos: Vector3) -> void:
	if _labels.is_empty() or cam == null:
		return
	var shown := targeted
	if not shown:
		shown = global_position.distance_to(player_pos) <= NAME_RANGE 				and option("names_companions" if companion else "names_gamebots")
	if not shown and _size >= 0 and not (_labels[0] as Label3D).visible:
		return                                             # (hidden and already sized: nothing to do)
	var vp_h := get_viewport().get_visible_rect().size.y
	var size := maxi(8, roundi(EM * vp_h))
	var col := TARGETED if targeted else (ENEMY if _enemy() else (GROUP if grouped else FRIENDLY))
	var pixel := 2.0 * tan(deg_to_rad(cam.fov * 0.5)) / vp_h
	for k in _labels.size():
		var l: Label3D = _labels[k]
		if l.visible != shown:
			l.visible = shown
		# sized whether shown or not (a name first shown later kept Label3D's default size - huge, owner)
		if size != _size or not is_equal_approx(l.pixel_size, pixel):
			l.pixel_size = pixel
			l.font_size = size if k == 0 else roundi(size * 0.8)
			l.outline_size = maxi(3, roundi(l.font_size * 0.18))
			l.offset = Vector2(0, UiArt.font(true).get_height(roundi(size * 0.8)) if k == 0 and _labels.size() > 1 else 0.0)
		if shown and l.modulate != col:
			l.modulate = col
	_size = size
