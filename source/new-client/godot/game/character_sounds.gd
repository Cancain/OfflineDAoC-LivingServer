class_name CharacterSounds
extends Node3D
## A character's own sounds from the client's creature sheet (app/sounds/cc_creatures.csv, exported by
## pipeline/build_sounds.py --creatures=<sets>; monsters.csv "Sound Set" picks the row, Celt male = 8).
##   move_dirt   each footstep on ground            (Celt: g_Step_OnDirtSmall = walk1..4.wav)
##   move_water  each footstep while wading         (q_StepWater+Slosh: wet step, then a slosh 250 ms later)
##   swim        each swim stroke at the surface    (g_Swimstroke_Small: the client hard-codes it, cc_groups note)
## The client's kfa files carry no step markers and the sheet only says "triggered with each step", so footfalls are
## read from the client animation itself: each clip's foot-bone heights are sampled once (forward kinematics over the
## clip's own tracks) and a step plays when playback passes the moment a foot comes down. Hands for swim strokes.
## Distance: the row's r1..r2 (units) as a linear fade from the listener (mine; the client's rolloff is not known).

const M := 0.025
const MOVE_CLIPS := ["run", "walk", "walk_back", "strafe_left", "strafe_right"]
const SAMPLES := 96

var sheet := {}                            # this character's cc_creatures row
var index := {}                            # content/sounds/sounds.json
var surface := "dirt"                      # "dirt", "water" (wading) or "swim"; set by the owner each frame
var enabled := true
var step_log: Array = []                   # debug: [clip, surface, msec] of the last steps
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _contacts := {}                        # clip -> sorted contact times (seconds)
var _last_clip := ""
var _last_pos := 0.0
static var _streams := {}                  # file -> AudioStream, shared by every character (was one cache each)
static var _voice_ends: Array = []         # when each sound playing now ends (ticks ms), every character together
const MAX_VOICES := 48                     # a raid's 250 casters: the nearest / loudest get a voice
var _rng := RandomNumberGenerator.new()


static var _index_cache = null               # sounds.json, parsed once for every character (it was once per NPC)


## steps = false: no footstep timing (NPCs - footsteps are only your own in the original game; finding the foot
## contacts walked every move clip's bones, a large share of building each NPC).
func setup(model: Node3D, anim: AnimationPlayer, sound_set: int, steps := true) -> void:
	_rng.randomize()
	_anim = anim
	var found := model.find_children("*", "Skeleton3D", true, false)
	_skel = found[0] if found.size() > 0 else null
	if _index_cache == null:
		_index_cache = JSON.parse_string(FileAccess.get_file_as_string("res://content/sounds/sounds.json"))
	var idx = _index_cache
	if idx == null or _skel == null or _anim == null:
		return
	index = idx
	sheet = index.get("creatures", {}).get(str(sound_set), {})
	if not steps:
		enabled = false
		set_physics_process(false)
		return
	for clip in MOVE_CLIPS:
		_contacts[clip] = _find_contacts(clip, ["Bip01 L Foot", "Bip01 R Foot"])
	_contacts["swim"] = _find_contacts("swim", ["Bip01 L Hand", "Bip01 R Hand"])


## Footsteps on / off after setup (a steed you ride: the client's creature sheet row 41 is "horse (also player mount)"
## and its move_dirt is g_Gallop_OnDirt - owner 2026-10-17: no gallop riding a stable master's horse; NPC views are
## built with steps off).
func set_steps(on: bool) -> void:
	if on and _contacts.is_empty() and _skel and _anim:
		for clip in MOVE_CLIPS:
			_contacts[clip] = _find_contacts(clip, ["Bip01 L Foot", "Bip01 R Foot"])
	enabled = on
	set_physics_process(on)


## Contact moments of the given bones in one clip: where each bone reaches the bottom of its swing.
func _find_contacts(clip: String, bones: Array) -> Array:
	if not _anim.has_animation(clip):
		return []
	var a := _anim.get_animation(clip)
	var out := []
	for bone_name in bones:
		var bone := _skel.find_bone(bone_name)
		if bone < 0:
			continue
		var ys := PackedFloat32Array()
		for i in SAMPLES:
			ys.append(_bone_height(a, bone, a.length * i / SAMPLES))
		var lo := ys[0]
		var hi := ys[0]
		for y in ys:
			lo = minf(lo, y)
			hi = maxf(hi, y)
		if hi - lo < 0.02:
			continue                               # this bone barely moves in this clip
		var near := lo + (hi - lo) * 0.12          # "down": within the lowest 12 % of the swing
		for i in SAMPLES:
			var prev := ys[(i - 1 + SAMPLES) % SAMPLES]
			if ys[i] <= near and prev > near:      # the frame the bone comes down
				out.append(a.length * i / SAMPLES)
	out.sort()
	var merged := []                              # both hands/feet together (the swim stroke) = one sound
	for t in out:
		if merged.is_empty() or t - merged[-1] > 0.15:
			merged.append(t)
	if merged.size() > 1 and merged[0] + a.length - merged[-1] <= 0.15:
		merged.pop_back()
	return merged


## Height of a bone in skeleton space at time t, from the clip's own tracks (rest pose where a track is missing).
func _bone_height(a: Animation, bone: int, t: float) -> float:
	var xf := Transform3D.IDENTITY
	var b := bone
	var chain := []
	while b >= 0:
		chain.push_front(b)
		b = _skel.get_bone_parent(b)
	for c in chain:
		var rest := _skel.get_bone_rest(c)
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var scl := rest.basis.get_scale()
		var path := NodePath("%s:%s" % [_anim.get_node(_anim.root_node).get_path_to(_skel), _skel.get_bone_name(c)])
		var tp := a.find_track(path, Animation.TYPE_POSITION_3D)
		var tr := a.find_track(path, Animation.TYPE_ROTATION_3D)
		var ts := a.find_track(path, Animation.TYPE_SCALE_3D)
		if tp >= 0:
			pos = a.position_track_interpolate(tp, t)
		if tr >= 0:
			rot = a.rotation_track_interpolate(tr, t)
		if ts >= 0:
			scl = a.scale_track_interpolate(ts, t)
		xf = xf * Transform3D(Basis(rot).scaled(scl), pos)
	return xf.origin.y


func _physics_process(_delta: float) -> void:
	if _anim == null or sheet.is_empty():
		return
	var clip := _anim.current_animation
	var pos := _anim.current_animation_position
	if clip != _last_clip:
		_last_clip = clip
		_last_pos = pos
		return
	var times: Array = _contacts.get(clip, [])
	if enabled and not times.is_empty():
		for t: float in times:
			var crossed: bool = (t > _last_pos and t <= pos) if pos >= _last_pos else (t > _last_pos or t <= pos)
			if crossed:
				_step(clip)
				break                              # at most one sound per frame
	_last_pos = pos


func _step(clip: String) -> void:
	step_log.append([clip, surface, Time.get_ticks_msec()])
	if step_log.size() > 64:
		step_log.pop_front()
	if clip == "swim":
		play_structure("g_Swimstroke_Small")       # surface stroke: hard-coded in the client (cc_groups.csv note)
	elif surface == "water":
		play_structure(sheet.get("move_water", ""))
	else:
		play_structure(sheet.get("move_dirt", ""))


## Play a cc_sounds name / cc_groups group (one member at random) / cc_queues queue (members in order).
## A creature-sheet event (cc_creatures.csv columns): attack (unarmed swing vocal), pain_light (< 10% of the
## defender's hit points), pain_medium, pain_heavy (criticals / styles), die, evade, splat.
func event(key: String, delay := 0.0) -> void:
	play_structure(String(sheet.get(key, "")), delay)


## A weapon-sheet event (cc_weapons.csv, the weapon's objects.csv sound set; 19 = weaponless): activate (drawn),
## deactivate, use (the swing), hit_light / hit_medium (< / >= 10% of the defender's hit points), parried, blocked.
func weapon(set_id: int, key: String, delay := 0.0) -> void:
	var sheet: Dictionary = index.get("weapons", {}).get(str(set_id), {})
	var name := String(sheet.get(key, ""))
	if name == "" and key in ["style_hit", "style_use"]:   # a set without its own style sounds (weaponless)
		name = String(sheet.get("hit_medium" if key == "style_hit" else "use", ""))
	play_structure(name, delay)


func play_structure(name: String, delay := 0.0) -> void:
	var key := name.strip_edges().to_lower()
	if key == "" or key == "s_null":
		return
	if key.begins_with("s_"):
		var row: Dictionary = index.get("named", {}).get(key, {})
		if not row.is_empty():
			_play_row(row, delay)
	elif key.begins_with("g_"):
		var members: Array = index.get("groups", {}).get(key, [])
		if not members.is_empty():
			play_structure(members[_rng.randi() % members.size()], delay)
	elif not key.begins_with("q_") and (index.get("named", {}) as Dictionary).has(key):
		_play_row(index.named[key], delay)                 # a row named without the s_ prefix (spell_eldgath)
	elif key.begins_with("q_"):
		var q: Dictionary = index.get("queues", {}).get(key, {})
		var gap := _rng.randf_range(float(q.get("interval_ms", [0, 0])[0]), float(q.get("interval_ms", [0, 0])[1])) / 1000.0
		var d := delay
		for m in q.get("members", []):
			play_structure(m, d)
			d += maxf(gap, 0.0)


var play_log: Array = []                   # debug: [sound name, gain] of what was asked to play


func _play_row(row: Dictionary, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if play_log.size() > 50:
		play_log.pop_front()
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(row["file"])
	p.bus = "Effects"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.pitch_scale = _rng.randf_range(row["rate"][0], row["rate"][1])
	var gain := _rng.randf_range(row["vol"][0], row["vol"][1])
	var cam := get_viewport().get_camera_3d()
	if cam:
		var r: Array = row.get("range_units", [0, 1000])
		var d := cam.global_position.distance_to(global_position) / M
		gain *= clampf(1.0 - (d - float(r[0])) / maxf(float(r[1]) - float(r[0]), 1.0), 0.0, 1.0)
	play_log.append([String(row.get("name", "")), snappedf(gain, 0.01)])
	# a crowd plays only so many at once (like the client's sound channels): once half the voices are busy a quiet
	# (far) sound is skipped, once all are busy every new one is
	# The voices are counted by when they end, not by a counter (owner 2026-10-14: every combat sound - swings, hits,
	# pain and death cries - had gone silent): a view parked by the server's RemoveObject is disabled, which paused
	# its sound mid-play - it never finished, its voice was never given back, and a session's leaked voices filled
	# the cap until no character sound played at all.
	var now := Time.get_ticks_msec()
	_voice_ends = _voice_ends.filter(func(t): return int(t) > now)
	var voices := _voice_ends.size()
	var cap: int = mini(MAX_VOICES, Perf.voices)
	if p.stream == null or gain <= 0.0 or voices >= cap or (voices >= cap / 2 and gain < 0.35):
		p.free()
		return
	p.volume_db = linear_to_db(gain)
	p.process_mode = Node.PROCESS_MODE_ALWAYS          # plays out even when its character's view is parked
	add_child(p)
	_voice_ends.append(now + int(p.stream.get_length() / maxf(p.pitch_scale, 0.1) * 1000.0) + 50)
	p.finished.connect(p.queue_free)
	p.play()


static var load_us := 0                          # time spent reading sound files (debug: tests/walk_perf.gd)


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		var t0 := Time.get_ticks_usec()
		_streams[file] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://content/sounds".path_join(file)))
		load_us += Time.get_ticks_usec() - t0
	return _streams[file]


func contacts_text() -> String:
	var parts := []
	for c in _contacts:
		parts.append("%s %s" % [c, str(_contacts[c].map(func(t): return snappedf(t, 0.01)))])
	return ", ".join(parts)
