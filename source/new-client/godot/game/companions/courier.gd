class_name Courier
extends Node3D
## The level-5 courier (bot plan phase 6, owner 2026-10-11): Hibernia's messenger fairy, Midgard's small wolf,
## Albion's glowing sphere comes up to you, says the innkeeper's message and goes. Only for the look - the quest is in
## your journal before it appears (Companions._check_courier). It is no NPC: nothing can target, fight or kill it, it
## ignores walls (flies / trots straight through, never stuck), follows you if you move, and leaves on a timer
## whatever happens (you die, start a fight, ride off - it is simply gone; a zone change frees it with the scene).

const ARRIVE_S := 6.0                       # the longest it takes to reach you
const STAY_S := 7.0
const LEAVE_S := 4.0

var _player: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _fly := 0.0
var _lines: Array = []
var _name := ""
var _phase := "arrive"
var _t := 0.0
var _from := Vector3.ZERO
var _away := Vector3.ZERO
var _npcs: NpcManager


## Seamless zones: you crossed a border and the scene moved by -d.
func rebase(d: Vector3) -> void:
	_from -= d
	_away -= d
	global_position -= d


func start(player: Node3D, npcs: NpcManager, spec: Dictionary, lines: Array) -> void:
	_player = player
	_npcs = npcs
	_lines = lines
	_name = String(spec.get("name", "a messenger"))
	_fly = float(spec.get("fly", 0.0))
	var all = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var info: Dictionary = (all as Dictionary).get(String(spec.get("model", "")), {}) if all is Dictionary else {}
	if info.has("gltf") and npcs:
		_model = npcs.instance_model(String(info.gltf))
	if _model == null:
		_model = Node3D.new()
	add_child(_model)
	_model.scale *= float(info.get("scale", 1.0))
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	_anim = players[0] if players.size() > 0 else null
	var back := Vector3(sin(player.call("facing")), 0, cos(player.call("facing")))
	_from = player.global_position + back.rotated(Vector3.UP, randf_range(-0.8, 0.8)) * 22.0 + Vector3(0, _fly + 0.0, 0)
	global_position = _from
	_play("run" if _fly <= 0.0 else "idle")


func _play(clip: String) -> void:
	if _anim:
		for c in [clip, "walk", "idle"]:
			if _anim.has_animation(c):
				_anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
				_anim.play(c, 0.2)
				return


func _ground(p: Vector3) -> float:
	return _npcs.ground_at(p) if _npcs else p.y


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	_t += delta
	var side := Vector3(cos(_player.call("facing")), 0, -sin(_player.call("facing")))
	var spot := _player.global_position + side * 1.6
	match _phase:
		"arrive":
			var to := spot - global_position
			to.y = 0.0
			var speed := maxf(to.length() / maxf(0.1, ARRIVE_S - _t), 6.0)
			if to.length() < 0.4 or _t >= ARRIVE_S:
				_phase = "stay"
				_t = 0.0
				_play("idle")
				PlayerData.message.emit(String(_lines[0]), "npc")
				if _lines.size() > 1:
					PlayerData.message.emit("%s says, %s" % [_name.substr(0, 1).to_upper() + _name.substr(1), String(_lines[1])], "npc")
			else:
				global_position += to.normalized() * minf(to.length(), speed * delta)
				look_at_from(to)
		"stay":
			global_position = global_position.lerp(spot, minf(1.0, delta * 3.0))   # keeps by you if you walk on
			var face := _player.global_position - global_position
			face.y = 0.0
			look_at_from(face)
			if _t >= STAY_S:
				_phase = "leave"
				_t = 0.0
				_away = global_position + (global_position - _player.global_position).normalized() * 30.0
				_play("run" if _fly <= 0.0 else "idle")
		"leave":
			var to := _away - global_position
			to.y = 0.0
			global_position += to.normalized() * minf(to.length(), 9.0 * delta)
			look_at_from(to)
			var fade := clampf(1.0 - _t / LEAVE_S, 0.0, 1.0)
			_model.scale = _model.scale.normalized() * maxf(0.001, _model.scale.length() * (0.985 if fade < 0.5 else 1.0))
			if _t >= LEAVE_S:
				queue_free()
				return
	var gy := _ground(global_position)
	var bob := sin(Time.get_ticks_msec() / 260.0) * 0.12 if _fly > 0.0 else 0.0
	global_position.y = gy + _fly + bob


func look_at_from(dir: Vector3) -> void:
	if dir.length() > 0.05:
		rotation.y = atan2(dir.x, dir.z)                  # monster models face +Z
