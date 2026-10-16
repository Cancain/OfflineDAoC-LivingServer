class_name HorseRoutes
extends Node
## Stable master horse routes (the old server's GameStableMaster / GameTaxi; content/world/routes.json from
## pipeline/build_routes.py):
## - buying a "Ticket to X" from a stable master hands it straight back to him; if the ticket's path starts within 500
##   units of him he takes it and a horse appears at the start ("Sorry, that ticket isn't for around here." if not);
## - the horse is the ticket's template mount, else the "horse" standing by the stable, sized for your race (Lurikeen /
##   Kobold 38 ... Firbolg 62, Troll 67); you mount after 0.4 s and it sets off after 4 s;
## - it runs the path at 1500 units / s capped by each point's MaxSpeed, waits WaitTime tenths of a second where a
##   point says so, crosses zone borders with you (the next zone loads and the ride goes on), and at the path's end
##   it is gone and you stand where it stopped; jumping or /dismount gets you off at once;
## - monsters leave a rider alone (StandardMobBrain skips players on a steed).
## Your companions ride too (owner 2026-10-11): each gets its own mount of the route's kind (sized for its race) and
## runs the same path a little behind the one before it - a line of riders, over zone borders with you, each getting
## off where its own mount stops (no vanishing, no catching up at a run). Their places on the path are kept with the
## ride across zone loads (ride.companions).

const RACE_SIZE := {"lurikeen": 38, "kobold": 38, "dwarf": 42, "inconnu": 45, "saracen": 48, "briton": 50, "celt": 50,
		"valkyn": 52, "avalonian": 52, "highlander": 55, "norse": 50, "elf": 52, "sylvan": 55, "firbolg": 62, "troll": 67}

static var ride := {}                                   # across zone loads: path, i, model, size, wait, yaw, start
static var _data := {}

var viewer: Node
var player: Node3D
var npcs: Node
var horse: Node3D
var _horse_anim: AnimationPlayer
var _saddle_bone := -1
var _saddle: Node3D
var _spine := -1
var _seat_local := Transform3D.IDENTITY
var _skeleton: Skeleton3D
var _mount_in := 0.0


static func routes() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/world/routes.json")) \
				if FileAccess.file_exists("res://content/world/routes.json") else null
		_data = parsed if parsed is Dictionary else {"routes": {}}
	return _data.get("routes", {})


func _ready() -> void:
	PlayerData.hook(self, PlayerData.bought, _on_bought)
	PlayerData.hook(self, PlayerData.dismount_requested, dismount)
	if not ride.is_empty():
		_show_horse()
		_mount_in = 0.0
		player.riding = true


## The zone's region offset in region units (zones_index.json).
var _origin := Vector2(-1, -1)


## Seamless zones: you rode over a border - the route goes on in the next zone's metres (the path is in region units,
## so only the origin changes); the mount moved by -d with the scene. The companions' mounts are theirs (GameBots).
func rebase(d: Vector3) -> void:
	_origin = Vector2(-1, -1)
	if horse and is_instance_valid(horse):
		horse.global_position -= d
	for cid in _riders:
		var h: Node3D = _riders[cid].horse
		if is_instance_valid(h):
			h.global_position -= d


func _zone_origin() -> Vector2:
	if _origin.x >= 0.0:
		return _origin
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json")) \
			if FileAccess.file_exists("res://content/zones/zones_index.json") else {}
	var me: Dictionary = (idx as Dictionary).get(str(int(viewer.zone.info.id)), {}) if idx is Dictionary else {}
	_origin = Vector2(float(me.get("x", 0)) * 8192.0, float(me.get("y", 0)) * 8192.0)
	return _origin


func _local(p: Array) -> Vector3:
	var o := _zone_origin()
	return Vector3((float(p[0]) - o.x) * 0.025, float(p[2]) * 0.025, (float(p[1]) - o.y) * 0.025)


func _on_bought(id: String) -> void:
	var r: Dictionary = routes().get(id, {})
	if r.is_empty() or not ride.is_empty():
		return
	var stable: NpcState = null
	for s in npcs.states:
		var st: NpcState = s
		if st.spawn.get("role") == "stablemaster" and st.pos.distance_to(player.global_position) < 15.0:
			stable = st
			break
	if stable == null:
		return
	var start := _local(r.points[0])
	if absf(start.x - stable.pos.x) / 0.025 >= 500.0 or absf(start.z - stable.pos.z) / 0.025 >= 500.0:
		PlayerData.message.emit("Sorry, that ticket isn't for around here.", "system")
		return
	var slot := PlayerData.find_item(id)
	if slot >= 0:
		PlayerData.take_one(slot)
	var model := int((r.get("mount", {}) as Dictionary).get("model", 0))
	if model <= 0:
		model = 449                                       # GameTaxi's own model, unless a horse stands by
		for s in npcs.states:
			var h: NpcState = s
			if String(h.spawn.name) == "horse" and h.pos.distance_to(stable.pos) <= 400.0 * 0.025:
				model = int(h.spawn.model)
				break
	var race := String(PlayerData.character.get("race", "")).to_lower()
	var size := 50
	for k in RACE_SIZE:
		if race.begins_with(k):
			size = int(RACE_SIZE[k])
	var nxt := _local(r.points[1])
	ride = {"path": id, "i": 0, "model": model, "size": size, "wait": 4.0, "yaw": atan2(nxt.x - start.x, nxt.z - start.z),
			"rpos": [float(r.points[0][0]), float(r.points[0][1]), start.y]}
	_mount_companions(start, atan2(nxt.x - start.x, nxt.z - start.z))
	_show_horse()
	_mount_in = 0.4                                       # MountHorseAction 400 ms, HorseRideAction 4000 ms


func _show_horse() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var all: Dictionary = parsed if parsed is Dictionary else {}
	var info: Dictionary = (all.get("models", all) as Dictionary).get(str(int(ride.model)), {})
	if info.has("gltf"):
		horse = npcs.instance_model(String(info.gltf))
	if horse == null:
		horse = Node3D.new()
	add_child(horse)
	horse.scale *= float(ride.size) / 50.0 * float(info.get("scale", 1.0))
	var o := _zone_origin()
	horse.global_position = Vector3((float(ride.rpos[0]) - o.x) * 0.025, float(ride.rpos[2]), (float(ride.rpos[1]) - o.y) * 0.025)
	if not _flying():
		horse.global_position.y = npcs.ground_at(horse.global_position)
	horse.rotation.y = float(ride.yaw)
	var players := horse.find_children("*", "AnimationPlayer", true, false)
	_horse_anim = players[0] if players.size() > 0 else null
	var skels := horse.find_children("*", "Skeleton3D", true, false)
	_skeleton = skels[0] if skels.size() > 0 else null
	_saddle_bone = _skeleton.find_bone("saddle") if _skeleton else -1
	_saddle = horse.find_child("saddle*", true, false) as Node3D     # the model's saddle node (the rider's seat)
	# the saddle node is a plain node at the rest pose, not on the skeleton: carry it with the spine bone it hangs off
	# (Spine1) so the seat moves with the horse's back - the standing idle (head down to the grass) shifts the body
	# forward and left the rider over the rump (owner 2026-10-09)
	_spine = _skeleton.find_bone("Bip01 Spine1") if _skeleton else -1
	if _saddle and _spine >= 0:
		_seat_local = (_skeleton.global_transform * _skeleton.get_bone_global_rest(_spine)).affine_inverse() * _saddle.global_transform
	_horse_play("idle")


func _horse_play(clip: String) -> void:
	if _horse_anim and _horse_anim.has_animation(clip) and _horse_anim.current_animation != clip:
		_horse_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_horse_anim.play(clip, 0.2)


## Where the rider sits: the horse's saddle bone, else 1.3 m up its back.
func _seat() -> Vector3:
	if _saddle and _spine >= 0:
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_spine) * _seat_local).origin
	if _saddle:
		return _saddle.global_position
	if _skeleton and _saddle_bone >= 0:
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_saddle_bone)).origin
	return horse.global_position + Vector3(0, 1.3 * horse.scale.y, 0)


func _physics_process(delta: float) -> void:
	if ride.is_empty() or horse == null:
		return
	if _mount_in > 0.0:
		_mount_in -= delta
		if _mount_in <= 0.0:
			player.riding = true
			PlayerData.message.emit("You mount your steed.", "system")
		return
	var r: Dictionary = routes().get(String(ride.path), {})
	var pts: Array = r.get("points", [])
	if float(ride.wait) > 0.0:
		ride.wait = float(ride.wait) - delta
		_horse_play("idle")
	elif int(ride.i) >= pts.size():
		dismount()
		return
	else:
		var p: Array = pts[int(ride.i)]
		var target := _local(p)
		var to := target - horse.global_position
		var fly := _flying()
		if not fly:
			to.y = 0.0
		var d := to.length()
		if d < 0.625:                                     # within 25 units: the next point
			ride.i = int(ride.i) + 1
			ride.wait = int(p[4]) * 0.1
		else:
			var speed := float(_data.get("speed", 1500))
			if int(p[3]) > 0:
				speed = minf(speed, float(p[3]))
			var step := to / d * minf(d, speed * 0.025 * delta)
			horse.global_position += step
			if not fly:                                   # flights keep the path's heights (GameTaxi flies its points)
				horse.global_position.y = npcs.ground_at(horse.global_position)
			ride.yaw = lerp_angle(float(ride.yaw), atan2(to.x, to.z), minf(1.0, delta * 6.0))
			horse.rotation.y = float(ride.yaw)
			_horse_play("run")
	var o := _zone_origin()                               # region units: the ride carries on in the next zone
	ride.rpos = [o.x + horse.global_position.x / 0.025, o.y + horse.global_position.z / 0.025, horse.global_position.y]
	_ride_companions(delta)
	if player.riding:
		player.ride_clip = String((routes().get(String(ride.path), {}) as Dictionary).get("ride_clip", "ride_horse"))
		player.global_position = _seat()
		player.char_yaw = float(ride.yaw) + PI              # the horse model faces +Z, the player faces -Z (owner: rode backwards)
		player._apply_model_yaw()


## A Shrouded Isles flight (dragonfly / wyvern / gryphon ticket): the mount follows the path's heights.
func _flying() -> bool:
	return bool((routes().get(String(ride.get("path", "")), {}) as Dictionary).get("fly", false))


## Off the horse: it is gone and you stand where it was (forced at the path's end, or by jumping / /dismount).
func dismount() -> void:
	if ride.is_empty():
		return
	for cid in _riders.keys():                            # your companions get off where they are, too
		_rider_off(int(cid))
	var at := horse.global_position if horse else player.global_position
	ride = {}
	if horse:
		horse.queue_free()
		horse = null
	player.riding = false
	player.global_position = Vector3(at.x, npcs.ground_at(at) + 0.3, at.z)


# --- your companions riding behind you ----------------------------------------------------------------------------

const RIDER_GAP := 0.12                                   # seconds behind the rider in front (~4.5 m at a gallop)
var _riders := {}                                         # companion id -> {horse, parts}


func _gamebots() -> Node:
	return WorldLink.bots


## The companions with you mount up at the route's start, each a little further back, and set off in turn.
func _mount_companions(start: Vector3, yaw: float) -> void:
	var gb := _gamebots()
	if gb == null or not ("companions" in viewer) or viewer.companions == null:
		return
	var list := {}
	var k := 0
	for cid in gb.call("CompanionIds"):
		var f = viewer.companions.foe(int(cid))
		if f == null or not bool(f.get("alive")):
			continue
		k += 1
		var back := Vector3(-sin(yaw), 0, -cos(yaw)) * (3.5 * k)
		var o := _zone_origin()
		var at := start + back
		list[str(int(cid))] = {"i": 0, "wait": float(ride.wait) + RIDER_GAP * k, "yaw": yaw,
				"rpos": [o.x + at.x / 0.025, o.y + at.z / 0.025, at.y]}
	ride["companions"] = list


func _rider_size(cid: int) -> int:
	var rec := Companions.by_id(cid)
	var race := String(rec.get("race", "")).to_lower()
	for k in RACE_SIZE:
		if race.begins_with(k):
			return int(RACE_SIZE[k])
	return 50


func _ride_companions(delta: float) -> void:
	var list: Dictionary = ride.get("companions", {})
	if list.is_empty():
		return
	var gb := _gamebots()
	if gb == null:
		return
	var present: Array = Array(gb.call("CompanionIds")).map(func(x): return str(int(x)))
	var r: Dictionary = routes().get(String(ride.path), {})
	var pts: Array = r.get("points", [])
	var clip := String(r.get("ride_clip", "ride_horse"))
	var fly := _flying()
	var o := _zone_origin()
	for key in list.keys():
		if not present.has(key):
			continue                                      # (not in the world yet: arrives with the zone)
		var c: Dictionary = list[key]
		var cid := int(key)
		if not _riders.has(cid):
			_rider_on(cid, c, clip)
		var h: Node3D = _riders[cid].horse
		if float(c.wait) > 0.0:
			c.wait = float(c.wait) - delta
			_play_on(_riders[cid].parts, "idle")
		elif int(c.i) >= pts.size():
			_rider_off(cid)
			list.erase(key)
			continue
		else:
			var p: Array = pts[int(c.i)]
			var to := _local(p) - h.global_position
			if not fly:
				to.y = 0.0
			var d := to.length()
			if d < 0.625:
				c.i = int(c.i) + 1
				c.wait = int(p[4]) * 0.1
			else:
				var speed := float(_data.get("speed", 1500))
				if int(p[3]) > 0:
					speed = minf(speed, float(p[3]))
				h.global_position += to / d * minf(d, speed * 0.025 * delta)
				if not fly:
					h.global_position.y = npcs.ground_at(h.global_position)
				c.yaw = lerp_angle(float(c.yaw), atan2(to.x, to.z), minf(1.0, delta * 6.0))
				h.rotation.y = float(c.yaw)
				_play_on(_riders[cid].parts, "run")
		c.rpos = [o.x + h.global_position.x / 0.025, o.y + h.global_position.z / 0.025, h.global_position.y]
		# the rider on its seat, facing the way the mount goes (figures face +Z: the bots' facing is the player's)
		gb.call("PlaceCompanionRider", cid, _seat_on(_riders[cid].parts, h), rad_to_deg(float(c.yaw) + PI))


func _rider_on(cid: int, c: Dictionary, clip: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var all: Dictionary = parsed if parsed is Dictionary else {}
	var info: Dictionary = all.get(str(int(ride.model)), {})
	var h: Node3D = npcs.instance_model(String(info.gltf)) if info.has("gltf") else null
	if h == null:
		h = Node3D.new()
	add_child(h)
	h.scale *= float(_rider_size(cid)) / 50.0 * float(info.get("scale", 1.0))
	var o := _zone_origin()
	h.global_position = Vector3((float(c.rpos[0]) - o.x) * 0.025, float(c.rpos[2]), (float(c.rpos[1]) - o.y) * 0.025)
	if not _flying():
		h.global_position.y = npcs.ground_at(h.global_position)
	h.rotation.y = float(c.yaw)
	_riders[cid] = {"horse": h, "parts": _parts_of(h)}
	_gamebots().call("SetCompanionRiding", cid, true, clip)


func _rider_off(cid: int) -> void:
	if not _riders.has(cid):
		return
	var h: Node3D = _riders[cid].horse
	var at := h.global_position
	_riders.erase(cid)
	h.queue_free()
	var gb := _gamebots()
	if gb:
		gb.call("PlaceCompanionRider", cid, Vector3(at.x, npcs.ground_at(at) + 0.1, at.z), 0.0)
		gb.call("SetCompanionRiding", cid, false, "")


## A mount's animation and seat parts (the player's horse's rules: the saddle node carried by the spine bone).
func _parts_of(h: Node3D) -> Dictionary:
	var out := {}
	var players := h.find_children("*", "AnimationPlayer", true, false)
	out.anim = players[0] if players.size() > 0 else null
	var skels := h.find_children("*", "Skeleton3D", true, false)
	out.skel = skels[0] if skels.size() > 0 else null
	out.saddle = h.find_child("saddle*", true, false)
	out.spine = (out.skel as Skeleton3D).find_bone("Bip01 Spine1") if out.skel else -1
	out.saddle_bone = (out.skel as Skeleton3D).find_bone("saddle") if out.skel else -1
	if out.saddle and int(out.spine) >= 0:
		var sk: Skeleton3D = out.skel
		out.seat_local = (sk.global_transform * sk.get_bone_global_rest(int(out.spine))).affine_inverse() * (out.saddle as Node3D).global_transform
	return out


func _seat_on(parts: Dictionary, h: Node3D) -> Vector3:
	var sk: Skeleton3D = parts.get("skel")
	if parts.get("saddle") and int(parts.get("spine", -1)) >= 0 and parts.has("seat_local"):
		return (sk.global_transform * sk.get_bone_global_pose(int(parts.spine)) * (parts.seat_local as Transform3D)).origin
	if parts.get("saddle"):
		return (parts.saddle as Node3D).global_position
	if sk and int(parts.get("saddle_bone", -1)) >= 0:
		return (sk.global_transform * sk.get_bone_global_pose(int(parts.saddle_bone))).origin
	return h.global_position + Vector3(0, 1.3 * h.scale.y, 0)


func _play_on(parts: Dictionary, clip: String) -> void:
	var a: AnimationPlayer = parts.get("anim")
	if a and a.has_animation(clip) and a.current_animation != clip:
		a.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		a.play(clip, 0.2)
