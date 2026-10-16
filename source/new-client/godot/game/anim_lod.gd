class_name AnimLod
extends RefCounted
## Animation and shadow level of detail for every drawn character that isn't you - NPC and monster views (Npc) and the
## gamebots' / companions' figures (BotView) - one rule, one shared per-frame skeleton budget.
## Animation (Tir na Nog's 200 townsfolk cost 16 ms a frame animating every frame): within 8 m every frame, then
## 30 / 15 / 8 / 4 poses a second by distance, nothing off screen (the time is kept, so the pose is right when you look
## back). The clips still run at full speed - far figures just get fewer poses. Shadows: none beyond Perf.npc_shadow_m.
## The view's AnimationPlayer is switched to manual stepping; its owner calls step() from its (strided) tick.

## On screen within this of the camera: a pose every frame whatever the load (owner 2026-10-11: under load the
## governor shrank the full-rate range to 1.2 m and people walking by moved at 4-8 poses a second - jarring). The
## savings apply beyond it; these never count against the per-frame skeleton budget.
const NEAR_FULL_M := 22.0

## Every figure on screen posed every frame, at any distance (owner 2026-10-11: the bots and monsters are run by the
## world host now - the game only shows them - "fix the animations so they always run at full"). Off screen nothing is
## posed (the time is kept). False: the old distance tiers and skeleton budget below.
const FULL := true

## Posing on all the CPU's cores (owner 2026-10-11: "why is every animation burning one cpu core?"): each character's
## view (Npc / BotView) is its own sub-thread process group, so Godot steps them in parallel on its worker threads after
## the main thread's work each frame; the camera they measure against is a snapshot the main thread takes first
## (snapshot()); the skeleton budget is shared under a lock. --anim-single turns it off (all on the main thread).
static var threaded := not ("--anim-single" in OS.get_cmdline_user_args())
static var cam_pos := Vector3.ZERO
static var cam_planes: Array[Plane] = []
static var _snap_frame := -1
static var _lock := Mutex.new()
const THREAD_ORDER := 100                    # (after the main thread's group: the snapshot is taken by then)


## The main thread, each frame before the views step: where the camera is and what it sees.
static func snapshot(cam: Camera3D) -> void:
	var f := Engine.get_process_frames()
	if f == _snap_frame or cam == null:
		return
	_snap_frame = f
	cam_pos = cam.global_position
	cam_planes = cam.get_frustum()


## In the camera's view: a sphere VIEW_MARGIN_M round the figure's middle, not the point alone (owner 2026-10-15:
## companions whose head and shoulders still showed at the bottom of the screen, and figures at its edges, stopped
## animating and slid - the frozen run pose also left their cloaks flowing behind them after they stopped).
const VIEW_MARGIN_M := 2.0


static func in_view(p: Vector3, margin := VIEW_MARGIN_M) -> bool:
	for pl in cam_planes:
		if pl.distance_to(p) > margin:
			return false
	return true


## A view joins the parallel posing (its own sub-thread group, stepped after the main thread's work).
static func run_threaded(v: Node) -> void:
	if threaded:
		v.process_thread_group = Node.PROCESS_THREAD_GROUP_SUB_THREAD
		v.process_thread_group_order = THREAD_ORDER


## A child that must stay on the main thread (sounds, attached spell effects - shared caches, audio). The posing
## thread leaves these alone (_apply_shadow skips them: even looking at one from there is an error).
static func keep_on_main(n: Node) -> void:
	if threaded and n:
		n.process_thread_group = Node.PROCESS_THREAD_GROUP_MAIN_THREAD
		var id := n.get_instance_id()
		_lock.lock()
		_on_main[id] = true
		_lock.unlock()
		n.tree_exiting.connect(_forget_main.bind(id), CONNECT_ONE_SHOT)


static var _on_main := {}                    # instance ids of the main-thread children (keep_on_main)


static func _forget_main(id: int) -> void:
	_lock.lock()
	_on_main.erase(id)
	_lock.unlock()

var view: Node3D                             # whose distance / visibility counts
var model: Node3D                            # whose meshes cast the shadow
var anim: AnimationPlayer
var last_dist := 0.0                         # metres from the camera at the last step
var _dt := 0.0
var _shadow_check := 0.0
var _casting_shadow := true

static var _budget_frame := -1
static var _budget := 0
static var prof_anim_us := 0                 # debug timing (tests/crowd_probe.gd)
static var prof_anim_n := 0


func _init(v: Node3D, m: Node3D, a: AnimationPlayer) -> void:
	view = v
	model = m
	anim = a
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func step(delta: float, cam: Camera3D) -> void:
	if threaded:
		_step_threaded(delta)
		return
	# a stopped player (a one-shot clip that ended: a cast, a swing, a death) holds its last pose; advancing it anyway
	# cost 15x a playing one (0.6 ms each) and a crowd of 250 casters fell to 7 fps (tests/crowd_probe.gd)
	if anim == null or not view.visible or not anim.is_playing():
		_dt = 0.0
		return
	_dt += delta
	# The skeleton + skin update after an advance is the cost of a crowd (~0.25 ms a character, tests/crowd_probe.gd):
	# off screen nothing is updated; on screen the rate falls with distance (Perf stretches the distances as a fight gets
	# busy), and only so many characters beyond 8 m update in one frame - the ones that miss go first next frame.
	var step_s := 0.0
	var d := 0.0
	if cam and Perf.brute:                  # FPS target OFF: every skeleton, every frame, on screen or not
		last_dist = view.global_position.distance_to(cam.global_position)
		_shadow_tick(delta, 0.0)
		anim.advance(_dt)
		_dt = 0.0
		return
	if cam:
		last_dist = view.global_position.distance_to(cam.global_position)
		snapshot(cam)                                     # (once a frame: the camera's planes)
		if not in_view(view.global_position + Vector3(0, 1, 0)):
			_dt = minf(_dt, 2.0)
			_shadow_tick(delta, 1e9)
			return
		if FULL or last_dist < NEAR_FULL_M:
			_shadow_tick(delta, last_dist)
			var tn := Time.get_ticks_usec()
			anim.advance(_dt)
			prof_anim_us += Time.get_ticks_usec() - tn
			prof_anim_n += 1
			_dt = 0.0
			return
		d = last_dist / Perf.anim_range
		step_s = 0.0 if d < 8.0 else (1.0 / 30.0 if d < 20.0 else (1.0 / 15.0 if d < 40.0 else (0.125 if d < 80.0 else 0.25)))
	_shadow_tick(delta, d * Perf.anim_range)
	if _dt < step_s:
		return
	if d >= 8.0:
		var f := Engine.get_process_frames()
		if f != _budget_frame:
			_budget_frame = f
			_budget = Perf.anim_budget
		if _budget <= 0:
			return
		_budget -= 1
	var t0 := Time.get_ticks_usec()
	anim.advance(_dt)
	prof_anim_us += Time.get_ticks_usec() - t0
	prof_anim_n += 1
	_dt = 0.0


## The same rule from a worker thread: the camera snapshot instead of the camera node, the budget under the lock.
func _step_threaded(delta: float) -> void:
	if anim == null or not view.visible or not anim.is_playing():
		_dt = 0.0
		return
	_dt += delta
	if _snap_frame < 0:
		return
	var at := view.global_position
	last_dist = at.distance_to(cam_pos)
	if Perf.brute:
		_shadow_tick(delta, 0.0)
		anim.advance(_dt)
		_dt = 0.0
		return
	if not in_view(at + Vector3(0, 1, 0)):
		_dt = minf(_dt, 2.0)
		_shadow_tick(delta, 1e9)
		return
	if FULL or last_dist < NEAR_FULL_M:
		_shadow_tick(delta, last_dist)
		anim.advance(_dt)
		_dt = 0.0
		return
	var d := last_dist / Perf.anim_range
	var step_s := 0.0 if d < 8.0 else (1.0 / 30.0 if d < 20.0 else (1.0 / 15.0 if d < 40.0 else (0.125 if d < 80.0 else 0.25)))
	_shadow_tick(delta, last_dist)
	if _dt < step_s:
		return
	if d >= 8.0:
		_lock.lock()
		var f := Engine.get_process_frames()
		if f != _budget_frame:
			_budget_frame = f
			_budget = Perf.anim_budget
		var ok := _budget > 0
		if ok:
			_budget -= 1
		_lock.unlock()
		if not ok:
			return
	anim.advance(_dt)
	_dt = 0.0


## A one-shot clip just started (a swing, a flinch): pose it now, not at the next stride.
func pose_now() -> void:
	if anim:
		anim.advance(_dt)
		_dt = 0.0


## Characters beyond Perf.npc_shadow_m cast no shadow (checked twice a second; new gear is picked up at the next
## change - refresh_shadow() after a redress).
func _shadow_tick(delta: float, dist: float) -> void:
	_shadow_check -= delta
	if _shadow_check > 0.0 or model == null:
		return
	_shadow_check = 0.5 + fmod(float(view.get_instance_id() % 97) * 0.0103, 0.25)   # (no shared RNG from threads)
	var cast := dist <= Perf.npc_shadow_m
	if cast != _casting_shadow:
		_casting_shadow = cast
		_apply_shadow()


func refresh_shadow() -> void:
	_apply_shadow()


func _apply_shadow() -> void:
	_shadow_walk(model, GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _casting_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## The model's meshes, leaving out the main-thread children (spell effects: out of the posing thread's reach).
static func _shadow_walk(n: Node, setting: int) -> void:
	for c in n.get_children():
		_lock.lock()
		var skip := _on_main.has(c.get_instance_id())
		_lock.unlock()
		if skip:
			continue
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = setting
		_shadow_walk(c, setting)
