class_name ZoneAudio
extends Node
## Zone ambience exactly as the client's data drives it (zones/zoneNNN/sounds.dat, exported by build_sounds.py into
## content/zones/zoneNNN/audio.json; sound rows from app/sounds/cc_sounds.csv in content/sounds/sounds.json).
## Client files only: nothing is replaced or substituted. Per region:
##   - shapes (circles/rects, zone units) unless zone_wide; leaving/entering fades over fade_time
##   - Type 2 = loop while its time window + weather match (chance rolled each time it starts)
##   - Type 1 = every Period seconds roll Chance %, then play once (random_sound_spacing = min gap in the region)
##   - Start/End game time HHMM (wraps past midnight; 0/0 = always); Weather 0 any / 1 clear / 2 raining / 3 fog
##   - version 2 rows (162 zones) name a structure instead of an id: an s_ row, a g_ group (one member at random each
##     time), a q_ queue (its members in turn, interval apart); their spacing may be a range ("20-60" s) and a 9th
##     field 2 = underwater only (1.65 has no diving: never). Owner 2026-10-10: Muspelheim's lava was silent.
##   - Volume 0..100 (music uses 111) x the cc_sounds vol range; rate range -> pitch; pan range -> panned bus
##   - sound_type 2 = ambient music (Music bus, one part per region at a time); fade_on_mp3 ducks it under mp3s
## Interpretations where the client data is silent (mine, see WORLD IMPORT LESSONS.md): a random sound doesn't
## retrigger while it is still playing; a full polygroup (cc_sounds POLYGROUPS: ambient_sfx limit 6, cutoff 1) steals
## its oldest voice with a short fade (cutoff 1), or skips the new sound (any other cutoff, e.g. TutorialVO's 2).

const M := 0.025
const PAN_STEPS := 9                       # panned buses at -1 .. +1
const RAIN_LEVEL := 0.125                  # storm level where SkySystem starts drawing rain

var sky: SkySystem
var listener: Node3D
var data := {}
var table := {}
var named := {}                            # sounds.json 'named' / 'groups' / 'queues' (version 2 structure names)
var groups := {}
var queues := {}
var mp3_table := {}
var polygroups := {}
var _regions: Array = []
var _streams := {}
var _rng := RandomNumberGenerator.new()
var _mp3: AudioStreamPlayer
var _voices := {}                          # polygroup -> playing one-shots, oldest first
var _time := 0.0
var stats := {}                            # debug: region name -> {played, full}


static func ensure_buses() -> void:
	for bus_name in ["Ambient", "Music"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	# the zone's own music goes through ZoneMusic (into Music, so the music volume still applies) - it fades out
	# under the battle music while the player is in attack mode
	if AudioServer.get_bus_index("ZoneMusic") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "ZoneMusic")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Music")
	for bus_name in ["Ambient", "Music"]:
		for k in PAN_STEPS:
			var n := "%s_pan%d" % [bus_name, k]
			if AudioServer.get_bus_index(n) >= 0:
				continue
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "ZoneMusic" if bus_name == "Music" else bus_name)
			var panner := AudioEffectPanner.new()
			panner.pan = lerpf(-1.0, 1.0, float(k) / (PAN_STEPS - 1))
			AudioServer.add_bus_effect(i, panner)


## start = false: load everything but stay silent until begin() (owner 2026-10-09: the title music plays on through
## the loading screen; the zone's music starts only once you are in the world).
func setup(zone_dir: String, sky_system: SkySystem, follow: Node3D, start := true) -> void:
	sky = sky_system
	listener = follow
	_rng.randomize()
	ensure_buses()
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://content/sounds/sounds.json"))
	var a = JSON.parse_string(FileAccess.get_file_as_string(zone_dir.path_join("audio.json")))
	if idx == null or a == null:
		push_warning("ZoneAudio: no audio data for %s (run pipeline/build_sounds.py)" % zone_dir)
		return
	table = idx.get("sounds", {})
	named = idx.get("named", {})
	groups = idx.get("groups", {})
	queues = idx.get("queues", {})
	mp3_table = idx.get("mp3", {})
	polygroups = idx.get("polygroups", {})
	data = a
	for reg in data.get("regions", []):
		var state := {"def": reg, "fade": 0.0, "last_random": -1e9, "busy": null, "sounds": []}
		for s in reg["sounds"]:
			state["sounds"].append({"def": s, "player": null, "gain": 0.0, "rolled": false, "on": false,
					"next": _time + _rng.randf() * maxf(float(s["period"]), 1.0)})   # stagger the first rolls
		_regions.append(state)
	_mp3 = AudioStreamPlayer.new()
	_mp3.bus = "ZoneMusic"
	add_child(_mp3)
	if start:
		begin()
	else:
		set_process(false)


func begin(entry_music := true) -> void:
	set_process(true)
	if entry_music and data.get("entry_music_id") != null:
		play_mp3(int(data["entry_music_id"]))


const CROSS_FADE_S := 2.0                  # a zone line crossed: the old zone's sounds fade out over this


## Crossing a zone line inside a region - no loading screen (owner 2026-10-14: "when I cross zone lines my music
## abruptly resets its track"; the zone audio was thrown away and built again, as when zones had loading screens).
## This zone's beds and one-shots fade out while `next` (set up, not begun) comes in; the entry music still playing
## goes on in `next` when it is the next zone's own entry track too (else it fades out here and the next zone's
## starts), and the battle music carries on. Returns whether `next` should start its entry music.
func hand_over(next: ZoneAudio) -> bool:
	set_process(false)
	var start_entry := true
	var next_id = next.data.get("entry_music_id")
	if next_id == null or int(next_id) == _mp3_id:       # the same track (or none of the next zone's): not again -
		start_entry = false                                # it plays on if it still is, else the realm stays quiet
		next._mp3_id = _mp3_id
		if _mp3 and _mp3.playing:
			next._mp3.queue_free()
			_mp3.reparent(next)
			next._mp3 = _mp3
			_mp3 = null
	if _battle:
		if _battle_tween:
			_battle_tween.kill()
		_battle.reparent(next)
		next._battle = _battle
		_battle = null
	var tw := create_tween().set_parallel(true)
	var any := false
	for c in get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
			tw.tween_property(c, "volume_db", -60.0, CROSS_FADE_S)
			any = true
	if any:
		tw.chain().tween_callback(queue_free)
	else:
		tw.kill()
		queue_free()
	return start_entry


## Attack mode: the client's hard-coded battle tracks (cc_mp3s.csv 4 combat.mp3 / 22 combat2.mp3, "hard-coded; not
## referenced on mp3 sheet") take over from the zone music; leaving attack mode fades back (owner: "when in attack
## mode the music switches from zone music to battle music").
func set_battle(on: bool) -> void:
	if _battle == null:
		_battle = AudioStreamPlayer.new()
		_battle.bus = "Music"
		add_child(_battle)
	var zone_bus := AudioServer.get_bus_index("ZoneMusic")
	if _battle_tween:
		_battle_tween.kill()
	_battle_tween = create_tween().set_parallel(true)
	if on:
		var row: Dictionary = mp3_table.get(["4", "22"][_rng.randi() % 2], {})
		if not row.is_empty() and not _battle.playing:
			var st := AudioStreamMP3.new()
			st.data = FileAccess.get_file_as_bytes("res://content/sounds".path_join(row["file"]))
			st.loop = true
			_battle.stream = st
			_battle.volume_db = -40.0
			_battle.play()
		_battle_tween.tween_property(_battle, "volume_db", 0.0, 1.5)
		_battle_tween.tween_method(func(v: float): AudioServer.set_bus_volume_db(zone_bus, v),
				AudioServer.get_bus_volume_db(zone_bus), -60.0, 1.5)
	else:
		_battle_tween.tween_property(_battle, "volume_db", -60.0, 2.5)
		_battle_tween.tween_method(func(v: float): AudioServer.set_bus_volume_db(zone_bus, v),
				AudioServer.get_bus_volume_db(zone_bus), 0.0, 2.5)
		_battle_tween.chain().tween_callback(_battle.stop)


var _battle: AudioStreamPlayer
var _battle_tween: Tween


var _mp3_id := -1                          # the entry music track playing (cc_mp3s id)


func play_mp3(id: int) -> void:
	var row: Dictionary = mp3_table.get(str(id), {})
	if row.is_empty():
		return
	_mp3_id = id
	var st := AudioStreamMP3.new()
	st.data = FileAccess.get_file_as_bytes("res://content/sounds".path_join(row["file"]))
	_mp3.stream = st
	_mp3.play()


func _process(delta: float) -> void:
	if data.is_empty() or sky == null or listener == null:
		return
	_time += delta
	var p := listener.global_position / M          # zone units: x east, z south
	var minute := fposmod(sky.hour() * 60.0, 1440.0)
	var raining := sky.storm > RAIN_LEVEL
	var mp3_on := _mp3.playing
	for st in _regions:
		var reg: Dictionary = st["def"]
		var inside := bool(reg["zone_wide"]) or _inside(reg["shapes"], p.x, p.z)
		if bool(reg.get("fade_on_mp3", false)) and mp3_on:
			inside = false
		var fade_time := maxf(float(reg["fade_time"]), 0.1)
		st["fade"] = move_toward(st["fade"], 1.0 if inside else 0.0, delta / fade_time)
		var music := int(reg["sound_type"]) == 2
		for snd in st["sounds"]:
			var s: Dictionary = snd["def"]
			var active := _in_window(minute, int(s["start"]), int(s["end"])) and _weather_ok(int(s["weather"]), raining) 					and int(s.get("env", 1)) != 2           # underwater-only rows: no diving in 1.65
			if int(s["type"]) == 2:
				_loop(st, snd, active and inside, fade_time, delta, music)
			elif _time >= snd["next"]:
				var lo := maxf(float(s["period"]), 1.0)
				snd["next"] = _time + (_rng.randf_range(lo, maxf(lo, float(s["period_max"]))) if s.has("period_max") else lo)
				if active and st["fade"] > 0.5 and _rng.randf() * 100.0 < float(s["chance"]):
					_one_shot(st, snd, music)


func _loop(st: Dictionary, snd: Dictionary, want: bool, fade_time: float, delta: float, music: bool) -> void:
	var s: Dictionary = snd["def"]
	if want and not snd["on"]:                     # just became active: roll its chance once
		snd["on"] = true
		snd["rolled"] = _rng.randf() * 100.0 < float(s["chance"])
	elif not want:
		snd["on"] = false
	var target := 1.0 if (snd["on"] and snd["rolled"]) else 0.0
	snd["gain"] = move_toward(snd["gain"], target, delta / fade_time)
	var player: AudioStreamPlayer = snd["player"]
	if snd["gain"] <= 0.0:
		if player != null:
			player.queue_free()
			snd["player"] = null
		return
	if player == null:
		var row: Dictionary = _row_of(s)
		if row.is_empty():
			return                                 # dead reference: silent in the client too
		player = _make_player(row, true, music)
		snd["player"] = player
		snd["vol"] = _pick(row["vol"])
		player.play(_rng.randf() * player.stream.get_length())   # don't start every bed at its first sample
	player.volume_db = linear_to_db(maxf(float(s["volume"]) / 100.0 * snd["vol"] * snd["gain"], 0.0001))


## The cc_sounds row a sound plays now: its id (version 1), or its structure (version 2): an s_ row as is, a g_ group's
## member picked at random (groups nest), a q_ queue's next member in turn.
func _row_of(s: Dictionary) -> Dictionary:
	var name := String(s.get("name", ""))
	if name == "":
		return table.get(str(int(s["id"])), {})
	return _resolve(name, 0)


var _queue_at := {}                        # queue name -> the member it plays next


func _resolve(name: String, depth: int) -> Dictionary:
	var key := name.strip_edges().to_lower()
	if depth > 6 or key == "" or key == "s_null":
		return {}
	if named.has(key):
		return named[key]
	if groups.has(key):
		var members: Array = groups[key]
		return _resolve(String(members[_rng.randi() % members.size()]), depth + 1) if not members.is_empty() else {}
	if queues.has(key):
		var members: Array = queues[key].get("members", [])
		if members.is_empty():
			return {}
		var i := int(_queue_at.get(key, 0)) % members.size()
		_queue_at[key] = i + 1
		return _resolve(String(members[i]), depth + 1)
	return {}


func _one_shot(st: Dictionary, snd: Dictionary, music: bool) -> void:
	var s: Dictionary = snd["def"]
	var row: Dictionary = _row_of(s)
	if row.is_empty():
		return
	if _time - st["last_random"] < float(st["def"]["random_sound_spacing"]):
		return
	if snd["player"] != null and is_instance_valid(snd["player"]):
		return                                     # still playing
	if music and st["busy"] != null and is_instance_valid(st["busy"]):
		return                                     # one music part per region at a time
	var group: String = row.get("polygroup", "")
	var stat: Dictionary = stats.get_or_add(st["def"]["name"], {"played": 0, "full": 0})
	if group != "" and polygroups.has(group):
		var voices: Array = _voices.get_or_add(group, [])
		voices = voices.filter(func(v): return is_instance_valid(v) and v.playing and not v.has_meta("stolen"))
		_voices[group] = voices
		if voices.size() >= int(polygroups[group]["limit"]):
			stat["full"] += 1
			if int(polygroups[group]["cutoff"]) != 1:
				return
			var old: AudioStreamPlayer = voices.pop_front()
			old.set_meta("stolen", true)
			var tw := create_tween()
			tw.tween_property(old, "volume_db", -60.0, 0.25)
			tw.tween_callback(old.queue_free)
	stat["played"] += 1
	var player := _make_player(row, false, music)
	player.volume_db = linear_to_db(maxf(float(s["volume"]) / 100.0 * _pick(row["vol"]) * st["fade"], 0.0001))
	snd["player"] = player
	st["last_random"] = _time
	if music:
		st["busy"] = player
	if group != "" and _voices.has(group):
		_voices[group].append(player)
	player.finished.connect(player.queue_free)
	player.play()


func _make_player(row: Dictionary, loop: bool, music: bool) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = _stream(row["file"], loop)
	player.set_meta("snd", String(row.get("name", "")))     # which client sound it is (debug_text, probes)
	player.pitch_scale = _pick(row["rate"])
	var pan := _pick(row["pan"])
	var k := clampi(roundi((pan + 1.0) * 0.5 * (PAN_STEPS - 1)), 0, PAN_STEPS - 1)
	player.bus = "%s_pan%d" % ["Music" if music else "Ambient", k]
	add_child(player)
	return player


static var load_us := 0                          # time spent reading sound files (debug: tests/walk_perf.gd)


func _stream(file: String, loop: bool) -> AudioStream:
	var key := file + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var t0 := Time.get_ticks_usec()
	var st := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://content/sounds".path_join(file)))
	load_us += Time.get_ticks_usec() - t0
	Perf.proc_add("sound loads", Time.get_ticks_usec() - t0)   # (a first play reads its file: the live log)
	if loop and st != null:
		var frame_bytes := (2 if st.stereo else 1) * 2
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / frame_bytes
	_streams[key] = st
	return st


func _pick(r) -> float:
	return _rng.randf_range(float(r[0]), float(r[1]))


static func _in_window(minute: float, start: int, end: int) -> bool:
	if start == 0 and end == 0:
		return true
	var a := (start / 100) * 60 + start % 100
	var b := (end / 100) * 60 + end % 100
	return (minute >= a and minute <= b) if a <= b else (minute >= a or minute <= b)


static func _weather_ok(w: int, raining: bool) -> bool:
	# 3 = fog: the 1.65 sky (sky_*.dat) has no fog weather of its own, so those beds stay quiet (mine)
	return w == 0 or (w == 1 and not raining) or (w == 2 and raining)


static func _inside(shapes: Array, x: float, y: float) -> bool:
	for sh in shapes:
		if sh.has("circle"):
			var c: Array = sh["circle"]
			if Vector2(x - c[0], y - c[1]).length() <= c[2]:
				return true
		elif sh.has("rect"):
			var r: Array = sh["rect"]
			if x >= minf(r[0], r[2]) and x <= maxf(r[0], r[2]) and y >= minf(r[1], r[3]) and y <= maxf(r[1], r[3]):
				return true
	return false


func debug_text() -> String:
	var playing := 0
	for c in get_children():
		if c is AudioStreamPlayer and c.playing:
			playing += 1
	return "audio: %d voices%s" % [playing, " + entry music" if _mp3 != null and _mp3.playing else ""]
