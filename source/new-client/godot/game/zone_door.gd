class_name ZoneDoor
extends Node3D
## One door leaf of a zone object (pipeline/nif_static.py nif_doors): its panel and collision, posed closed / open
## from the NIF's own keyframes. Click it to open (the client's way); it closes again after STAYS_OPEN seconds
## (old server GameDoor STAYS_OPEN_DURATION 5000 ms). Its collision moves with it.
## Sound: the client's cc_doors row given by the door's flag (pipeline/build_sounds.py --doors: flag 1, the wooden
## metal-hinged door, for every door outside dungeons, as the old server sent it), played at the door.

const STAYS_OPEN := 5.0
const PICK_LAYER := 1 << 10                 # layer 11: doors (clicks)

var closed := Transform3D.IDENTITY          # in its zone's frame (the ZoneLoader it hangs on - seamless zones move
var opened := Transform3D.IDENTITY          # the zone, so world transforms went stale at a border crossing)
var seconds := 1.0
var is_open := false
var _t := 0.0                               # 0 closed .. 1 open
var _target := 0.0
var _timer := 0.0
var partner: ZoneDoor                       # the other leaf of a double door opens with it
var center := Vector3.INF                   # the middle of the closed leaf (zone frame): the doorway - doorway()
var sound_flag := 0                         # cc_doors row (0: silent)
var door_id := -1                           # the client's door id (ZoneLoader._make_doors) - what the server knows it by
var server_driven := false                  # the server's game: it opens / closes the door (DoorState), no timer here
static var _sounds = null                   # content/sounds/sounds.json
static var _streams := {}


func setup(closed_xf: Transform3D, open_xf: Transform3D, open_seconds: float) -> void:
	closed = closed_xf
	opened = open_xf
	seconds = maxf(open_seconds, 0.1)
	transform = closed


func add_panel(mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func add_collision(faces: PackedVector3Array, wall_layer: int) -> void:
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.collision_layer = wall_layer | PICK_LAYER
	body.collision_mask = 0
	body.set_meta("door", self)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	var box := AABB(faces[0], Vector3.ZERO)
	for f in faces:
		box = box.expand(f)
	center = closed * box.get_center()


func toggle() -> void:
	if is_open:
		close_door()
	else:
		open_door()


## The server's DoorState (owner 2026-10-14, keeps and relic temples: doors follow the server - opened for whoever it
## lets through, shut on enemies, broken keep doors stay open). Both leaves of a double door get it.
func set_server_state(open: bool) -> void:
	server_driven = true
	if open != is_open:
		if open:
			open_door(true)
		else:
			close_door(true)
		_sound("open" if open else "close")


func open_door(by_partner := false) -> void:
	is_open = true
	_target = 1.0
	_timer = STAYS_OPEN
	if not by_partner:
		_sound("open")                                  # one sound for a double door
	if partner and not partner.is_open:
		partner.open_door(true)


## Someone is still in the doorway (a gamebot or companion passing through - GameBots): it stays open a while longer.
## Without this the leaf swung shut on bots standing in the doorway and wedged them there (owner 2026-10-11, the hut
## door in Connla).
## The doorway's middle in the world now (bots open doors there - GameBots), INF when the leaf has no collision.
func doorway() -> Vector3:
	if center == Vector3.INF:
		return Vector3.INF
	var p := get_parent() as Node3D
	return p.to_global(center) if p and p.is_inside_tree() else center


func hold_open() -> void:
	if is_open:
		_timer = maxf(_timer, 2.0)
		if partner and partner.is_open:
			partner._timer = maxf(partner._timer, 2.0)


func close_door(by_partner := false) -> void:
	is_open = false
	_target = 0.0
	if not by_partner:
		_sound("close")
	if partner and partner.is_open:
		partner.close_door(true)


func _sound(which: String) -> void:
	if sound_flag <= 0:
		return
	if _sounds == null:
		_sounds = JSON.parse_string(FileAccess.get_file_as_string("res://content/sounds/sounds.json"))
	if not _sounds is Dictionary:
		return
	var id = (_sounds.get("doors", {}) as Dictionary).get(str(sound_flag), {}).get(which)
	var row: Dictionary = (_sounds.get("sounds", {}) as Dictionary).get(str(int(id)), {}) if id != null else {}
	if row.is_empty():
		return
	var file := String(row.file)
	if not _streams.has(file):
		_streams[file] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://content/sounds".path_join(file)))
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[file]
	p.bus = "Effects"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.pitch_scale = randf_range(float(row.rate[0]), float(row.rate[1]))
	var gain := randf_range(float(row.vol[0]), float(row.vol[1]))
	var cam := get_viewport().get_camera_3d()
	if cam:                                             # the row's r1..r2 (units) as a linear fade, as for NPC sounds
		var r: Array = row.get("range_units", [0, 1000])
		var d := cam.global_position.distance_to(_world(closed.origin)) / 0.025
		gain *= clampf(1.0 - (d - float(r[0])) / maxf(float(r[1]) - float(r[0]), 1.0), 0.0, 1.0)
	if gain <= 0.0:
		p.free()
		return
	p.volume_db = linear_to_db(gain)
	get_parent().add_child(p)                           # not on the leaf: it swings
	p.global_position = _world(closed.origin)
	p.finished.connect(p.queue_free)
	p.play()


func _process(delta: float) -> void:
	if is_open and not server_driven:
		_timer -= delta
		if _timer <= 0.0:
			close_door()
	if _t == _target:
		return
	_t = move_toward(_t, _target, delta / seconds)
	var q := closed.basis.get_rotation_quaternion().slerp(opened.basis.get_rotation_quaternion(), _t)
	transform = Transform3D(Basis(q).scaled(closed.basis.get_scale()), closed.origin.lerp(opened.origin, _t))


func _world(local: Vector3) -> Vector3:
	var p := get_parent() as Node3D
	return p.to_global(local) if p and p.is_inside_tree() else local
