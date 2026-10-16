extends Node
## Autoload "Perf": holds the frame rate on a target by trading detail for speed as the scene gets busy (owner
## 2026-10-10: full-quality textures and animation in a quiet town like Connla with 10-20 bots, much more aggressive
## savings in a dragon raid with 200-300 bots casting around you; 40+ fps). Every half second the smoothed frame
## time is compared with the target and one "load" level (0 = full detail .. 1 = most saving) moves up fast when
## below target and down slowly when comfortably above (hysteresis, no flicker). The level drives:
##   - how far NPCs animate every frame (Npc._animate_lod distances x anim_range),
##   - NPC shadow distance (npc_shadow_m),
##   - spell / effect particle density (particle_ratio, GPUParticles3D.amount_ratio),
##   - texture detail (the viewport's mipmap bias: sharp skins up close in town, softer in a crowd).
## No upscaler (owner 2026-10-10: native only for now).
## Two dials, not one (owner 2026-10-11: "if the gpu isn't under load why smudge my textures?"): the graphics card's own
## time per frame is measured (RenderingServer's GPU timer). When the frame is slow but the card finishes well inside
## it, the CPU is the limit - only the CPU savings rise (animation, skeleton budget, effect count, sounds, character
## shadow distance - each caster is drawn again per shadow split); texture sharpness and particles stay full. When the card is the limit, the GPU savings rise. A busy scene
## that is slow on both gets both.

const TARGETS := [0, 30, 40, 50, 60, 75, 90, 120, 144]

var target_fps := 60                       # 0 = off: brute force, no culling or level of detail anywhere
var brute := false                         # target_fps == 0 (read by Npc / NpcManager / SpellFx)
var level := 0.0                           # the larger of the two dials (tests read it)
var cpu_level := 0.0                       # 0 full detail .. 1 most saving: what costs the CPU
var gpu_level := 0.0                       # ...and what costs the graphics card
var fps := 60.0                            # smoothed
var gpu_ms := 0.0                          # the graphics card's time a frame (smoothed)

# what the level means right now (read by Npc / SpellFx every so often)
var anim_range := 1.0                      # x the NPC animation LOD distances
var npc_shadow_m := 60.0                   # NPCs beyond this cast no shadow
var anim_budget := 60                      # skeleton updates per frame beyond 8 m (Npc._animate_lod)
var particle_ratio := 1.0
var fx_range := 80.0                       # spell effects beyond this (metres from the camera) are not drawn
var max_effects := 300                     # spell effects alive at once (the nearest are kept)
var gather_range := 80.0                   # other casters' hand glows (the long-lived effects) only this close
var voices := 48                           # sounds at once (CharacterSounds)

var gpu_vendor := ""
var gpu_name := ""
var _t := 0.0
var _cpu_good := 0.0
var _gpu_good := 0.0
var _frame_ms := 16.7
var _gpu_on := false
var _gpu_left := 0.0


func _ready() -> void:
	gpu_vendor = RenderingServer.get_video_adapter_vendor()
	gpu_name = RenderingServer.get_video_adapter_name()
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(UiArt.settings_path)
	target_fps = int(cfg.get_value("performance", "target_fps", 60))
	_apply()


func set_option(key: String, value) -> void:
	match key:
		"target_fps": target_fps = int(value)
	_apply()


func _process(delta: float) -> void:
	_proc_frames += 1
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	var vp := get_viewport()
	if vp and not _gpu_on:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		_gpu_on = true
	_gpu_left -= delta
	if vp and _gpu_left <= 0.0:
		# once a second: each read makes the CPU wait for the render thread (Godot warns of it every frame)
		_gpu_left = 1.0
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		if g > 0.0:
			gpu_ms = g if gpu_ms <= 0.0 else lerpf(gpu_ms, g, 0.5)
	_t += delta
	_log_t += delta
	_phys_max = maxf(_phys_max, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_proc_max = maxf(_proc_max, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_slow = _slow + 1 if delta > 0.05 else _slow
	if _log_t >= 2.0:
		_log_t = 0.0
		_live_log()
	if _t < 0.5:
		return
	_t = 0.0
	fps = 1000.0 / maxf(_frame_ms, 0.1)
	if target_fps <= 0:
		if level != 0.0 or cpu_level != 0.0 or gpu_level != 0.0:
			cpu_level = 0.0
			gpu_level = 0.0
			level = 0.0
			_apply()
		return
	var target_ms := 1000.0 / target_fps
	var behind := fps < target_fps * 0.95
	# whose fault is a slow frame: the card is the limit when its own work nearly fills the frame or the target
	var gpu_bound := gpu_ms > 0.0 and (gpu_ms >= _frame_ms * 0.85 or gpu_ms >= target_ms * 0.9)
	var cpu_bound := gpu_ms <= 0.0 or gpu_ms < _frame_ms * 0.85            # (no GPU timer: treat as the CPU)
	var step := 0.15 if fps < target_fps * 0.75 else 0.06
	var changed := false
	if behind and cpu_bound:
		cpu_level = minf(cpu_level + step, 1.0)
		_cpu_good = 0.0
		changed = true
	elif cpu_level > 0.0 and (fps > target_fps * 1.2 or not behind):
		_cpu_good += 0.5
		if _cpu_good >= 3.0 and fps > target_fps * 1.2:
			cpu_level = maxf(cpu_level - 0.04, 0.0)
			changed = true
	if behind and gpu_bound:
		gpu_level = minf(gpu_level + step, 1.0)
		_gpu_good = 0.0
		changed = true
	elif gpu_level > 0.0:
		# the card has room (its work well inside the target): give its detail back - even while the frame is slow
		# for another reason; textures never stay smudged for a CPU-bound crowd
		var roomy := gpu_ms > 0.0 and gpu_ms < target_ms * 0.6
		if roomy or fps > target_fps * 1.2:
			_gpu_good += 0.5
			if _gpu_good >= (1.5 if roomy else 3.0):
				gpu_level = maxf(gpu_level - (0.08 if roomy else 0.04), 0.0)
				changed = true
		else:
			_gpu_good = 0.0
	if changed:
		level = maxf(cpu_level, gpu_level)
		_apply()


## Level 0 is full quality (a quiet town keeps every effect, shadow and animation); the cuts grow drastic toward
## level 1 (owner 2026-10-10: 60 fps matters more than detail in a 200-300 bot raid - far spell effects off, the
## nearest kept, distant bots animating slowly).
## Live performance log (owner 2026-10-11: "check my live performance tracking" - there was none): every 2 s one line in
## user://perf_live.log - fps, the frame's script process and physics times (worst in the 2 s), frames over 50 ms,
## the graphics card's time, draw calls, objects / nodes, video memory, the detail levels, the NPCs drawn and the bots
## run in this game. Kept short (rolled over at 2 MB).
var _log_t := 0.0
var _phys := {}                                  # part -> microseconds in physics ticks since the last line
var _phys_ticks := 0


func phys_add(part: String, usec: int) -> void:
	_phys[part] = int(_phys.get(part, 0)) + usec
	frame_parts["phys " + part] = int(frame_parts.get("phys " + part, 0)) + usec


## The frame's main-thread time by part (owner 2026-10-14: Tir na Nog 40 fps CPU-bound with 200 NPCs - which part?):
## the live log's "process a frame by part"; what's left of the process time is everything else (the NPC views'
## threaded posing waited on, engine work). Main thread only.
var _proc := {}
var _proc_frames := 0


var _proc_peak := {}                             # part -> its longest single call since the last line (a hitch)


var frame_parts := {}                            # the same, since a probe last took it (tests/walk_perf: per slow frame)


func proc_add(part: String, usec: int) -> void:
	_proc[part] = int(_proc.get(part, 0)) + usec
	frame_parts[part] = int(frame_parts.get(part, 0)) + usec
	if usec > int(_proc_peak.get(part, 0)):
		_proc_peak[part] = usec


func _physics_process(_delta: float) -> void:
	_phys_ticks += 1
var _phys_max := 0.0
var _proc_max := 0.0
var _slow := 0


func _live_log() -> void:
	var path := "user://perf_live.log"
	var f: FileAccess
	if FileAccess.file_exists(path) and FileAccess.open(path, FileAccess.READ).get_length() > 2_000_000:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path("user://perf_live.old.log"))
	f = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var scene := get_tree().current_scene
	var npcs = scene.get("npcs") if scene else null
	var drawn: int = (npcs.active as Dictionary).size() if npcs is NpcManager else -1
	var bots := -1
	var parts := ""
	var n := maxi(_phys_ticks, 1)
	for k in _phys:
		parts += "%s %.2f, " % [k, int(_phys[k]) / 1000.0 / n]
	if WorldLink.bots and WorldLink.bots.has_method("BotCount"):
		bots = int(WorldLink.bots.call("BotCount"))
		parts += String(WorldLink.bots.call("PhysReport"))
	parts = "%d ticks: %s" % [_phys_ticks, parts]
	_phys.clear()
	_phys_ticks = 0
	var fparts := ""
	var fn := maxi(_proc_frames, 1)
	for k in _proc:
		fparts += "%s %.2f (peak %.0f), " % [k, int(_proc[k]) / 1000.0 / fn, int(_proc_peak.get(k, 0)) / 1000.0]
	parts += " | process a frame by part (ms): " + fparts
	_proc.clear()
	_proc_peak.clear()
	_proc_frames = 0
	f.store_line(("[host] " if DisplayServer.get_name() == "headless" else "[game] ") + "%s fps %.0f | process %.1f max %.1f ms | physics %.1f max %.1f ms | slow frames %d | gpu %.1f ms | draws %d objs %d nodes %d | vram %d MB | cpu lvl %.2f gpu lvl %.2f | npcs drawn %d | bots %d" % [
		Time.get_time_string_from_system(), Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, _proc_max,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _phys_max, _slow, gpu_ms,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		cpu_level, gpu_level, drawn, bots] + " | physics a tick by part (ms): " + parts)
	f.close()
	_phys_max = 0.0
	_proc_max = 0.0
	_slow = 0


func _apply() -> void:
	brute = target_fps <= 0
	var c := cpu_level
	var g := gpu_level
	var both := maxf(c, g)                                  # effects cost both (scripts + particles)
	# the CPU's savings
	anim_range = lerpf(1.0, 0.15, c)
	anim_budget = int(lerpf(60.0, 8.0, c))
	voices = int(lerpf(48.0, 16.0, c))
	max_effects = int(lerpf(300.0, 30.0, sqrt(both)))
	fx_range = lerpf(80.0, 10.0, sqrt(both))
	gather_range = lerpf(80.0, 6.0, sqrt(both))
	npc_shadow_m = lerpf(60.0, 8.0, both)                   # shadows cost both: each caster drawn again per split
	# the graphics card's savings only
	particle_ratio = lerpf(1.0, 0.25, g)
	var vp := get_viewport()
	if vp:
		vp.texture_mipmap_bias = lerpf(0.0, 1.5, g * g)      # gentle at first, steep under heavy load
