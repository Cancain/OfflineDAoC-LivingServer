extends SceneTree
## ZoneLoader.proxy_faces (the client's tree stand-in box): a capsule walking at it from outside stops at the box's
## edge less its radius; one starting inside walks out (faces front outside, like the converted models' walls).
##   Godot --headless --path godot -s res://tests/proxy_box_probe.gd

var _body: CharacterBody3D
var _frames := 0
var _case := 0
var _results := []
const CASES := [[Vector3(-6, 0.0, 0.3), Vector3(1, 0, 0)], [Vector3(0.3, 0.0, 6), Vector3(0, 0, -1)],
		[Vector3(0.1, 0.0, 0.1), Vector3(1, 0, 0)]]


func _initialize() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = ZoneLoader.LAYER_WALL
	root.add_child(wall)
	var s := ConcavePolygonShape3D.new()
	# Pine#1 in Myrkwood: Radius 18 at scale 1.73 -> size 62 units, half (62 + 24) x 0.025 - 0.25 = 1.9 m
	s.set_faces(ZoneLoader.proxy_faces(18, 1.73, 100.0, Vector3(0, 100.0, 0), Player.STEP_LEAD))
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3(0, 100.0, 0)
	wall.add_child(cs)
	_body = CharacterBody3D.new()
	_body.collision_mask = ZoneLoader.LAYER_WALL
	_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cap := CapsuleShape3D.new()
	cap.radius = Player.STEP_LEAD
	cap.height = 1.8 - Player.COLLIDER_LIFT
	var bcs := CollisionShape3D.new()
	bcs.shape = cap
	bcs.position = Vector3(0, Player.COLLIDER_LIFT + cap.height * 0.5, 0)
	_body.add_child(bcs)
	root.add_child(_body)
	_start()


func _start() -> void:
	var c: Array = CASES[_case]
	_body.global_position = (c[0] as Vector3) + Vector3(0, 100.0, 0)
	_body.velocity = (c[1] as Vector3) * 7.0
	_frames = 0


func _physics_process(_delta: float) -> bool:
	_body.velocity = (CASES[_case][1] as Vector3) * 7.0
	_body.move_and_slide()
	_frames += 1
	if _frames < 120:
		return false
	_results.append(_body.global_position)
	print("[proxy] case %d from %s heading %s ended at %s" % [_case, CASES[_case][0], CASES[_case][1], _body.global_position.snapped(Vector3.ONE * 0.01)])
	_case += 1
	if _case >= CASES.size():
		var ok: bool = absf(_results[0].x + 2.15) < 0.05 and absf(_results[1].z - 2.15) < 0.05 and _results[2].x > 3.0
		print("[proxy] %s (expected: stops at x -2.15 and z 2.15 = (86 units) - from inside walks out)" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
		return true
	_start()
	return false
