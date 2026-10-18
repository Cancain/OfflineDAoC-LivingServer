class_name StyleTrail
extends Node3D
## The colour flash of a combat style, drawn as the client draws it (game.dll 0x46da71 / 0x46debd; owner 2026-10-17:
## the old afterimage copies looked "really delayed / slow framerate"): one ribbon swept between the held weapon's
## TRAILBASE and TRAILTIP nodes (content/weapons/trails.json, pipeline/add_weapon_trails.py), in the style's Red /
## Green / Blue (styles.csv). From Buildup ms into the swing to Duration ms the trail lays a new base / tip pair each
## time the tip has moved 5 units (0.125 m), 33 pairs at most; every pair fades over a third of a second as it ages,
## the first 0.2 s of the trail fade in and its last 0.1 s fade out. A weapon without the two nodes leaves no trail
## (as in the client). The ribbon follows the wielder (it's kept in the skeleton's frame) so a running swing doesn't
## smear behind.

const STEP := 0.125                          # m the tip moves before the next pair (the client's 5 units)
const MAX_PAIRS := 33                        # the client's strip: 0x42 vertices
const AGE_RATE := 3.0                        # the fade a pair gains each second (the client's V += dt x 3)
const ALPHA := 0.99
const BASE_ALPHA := 0.35                     # the edge at the weapon's base softer than its tip

var _points: Array = []                      # [[weapon model Node3D, base Vector3, tip Vector3]] (model space)
var _frame: Node3D                           # the wielder's skeleton: the ribbon kept in its space
var _color := Color.WHITE
var _wait := 0.0                             # s until the trail starts (Buildup)
var _span := 0.6                             # s it lays pairs for (Duration - Buildup)
var _t := 0.0                                # s since it started
var _pairs: Array = []                       # per weapon: [[base local, tip local, start fade, age]]
var _mesh: ImmediateMesh
var _mi: MeshInstance3D
static var _trails := {}


## Starts a trail on these weapon nodes (the held weapons' bone attachments) for one style.
static func play(world: Node, weapons: Array, trail: Variant) -> void:
	if not (trail is Dictionary) or weapons.is_empty() or int(trail.get("images", 0)) <= 0:
		return
	var t := StyleTrail.new()
	for w in weapons:
		if is_instance_valid(w):
			var p := _trail_points(w)
			if not p.is_empty():
				t._points.append(p)
				if t._frame == null:
					t._frame = (w as Node).get_parent() as Node3D
	if t._points.is_empty() or t._frame == null:
		t.free()
		return
	var rgb: Array = trail.get("rgb", [255, 255, 255])
	t._color = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	t._wait = float(trail.get("buildup", 400)) / 1000.0
	t._span = maxf(0.05, (float(trail.get("ms", 1000)) - float(trail.get("buildup", 400))) / 1000.0)
	for _i in t._points.size():
		t._pairs.append([])
	world.add_child(t)


## A held weapon's [model node, base, tip]: its Weapon_<model> holder's model and that model's client trail points.
static func _trail_points(attachment: Node) -> Array:
	if _trails.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://content/weapons/trails.json")) 				if FileAccess.file_exists("res://content/weapons/trails.json") else null
		_trails = j if j is Dictionary else {"_": []}
	for h in attachment.get_children():
		var n := String(h.name)
		if not n.begins_with("Weapon_") or (h as Node).get_child_count() == 0:
			continue
		var p: Array = _trails.get(n.trim_prefix("Weapon_"), [])
		if p.size() == 2:
			return [(h as Node).get_child(0), Vector3(p[0][0], p[0][1], p[0][2]), Vector3(p[1][0], p[1][1], p[1][2])]
	return []


## The weapons in a model's hands (the bone attachments on the Held / Hand bones, and the greaves' Shield bones - not the belt or back;
## a shield has no trail).
static func held(model: Node) -> Array:
	var out: Array = []
	if model == null or not is_instance_valid(model):
		return out
	for a in model.find_children("*", "BoneAttachment3D", true, false):
		var bone := String((a as BoneAttachment3D).bone_name)
		if bone in ["Bip01 R Held", "Bip01 L Held", "Bip01 R Hand", "Bip01 R Shield", "Bip01 L Shield"]:   # (greaves: Shield)
			out.append(a)
	return out


## A style row's trail: its own (styles.json) or, for the monster / pet rows of npcs.json / pets.json, the class
## style with the same StyleID.
static func trail_of(style: Dictionary, two_hand := false) -> Variant:
	var key := "trail_2h" if two_hand else "trail"
	if style.get(key) is Dictionary:
		return style[key]
	return ClassDb.style(int(style.get("styleid", 0))).get(key)


## A monster's / pet's style: the style is decided at the blow's impact, part way through its swing - the trail
## covers the rest of the swing from there (its Imagenum over half a second).
static func play_from_impact(world: Node, model: Node, style: Dictionary) -> void:
	var trail: Variant = trail_of(style)
	if not (trail is Dictionary):
		return
	var t: Dictionary = (trail as Dictionary).duplicate()
	t["buildup"] = 0
	t["ms"] = 500
	play(world, held(model), t)


## The server's game (0.36c): CombatAnimation carries the style as a styles.csv row - its trail from
## content/rules/style_fx.json (pipeline/build_style_anims.py: [Imagenum, Duration ms, Buildup ms, Red, Green, Blue,
## Hit Effect]). Null without one (owner 2026-10-16: no style colour flashes in the server's game - only the offline
## combat started trails).
static var _rows := {}


static func of_row(row: int) -> Variant:
	if _rows.is_empty():
		var t = JSON.parse_string(FileAccess.get_file_as_string("res://content/rules/style_fx.json")) 				if FileAccess.file_exists("res://content/rules/style_fx.json") else null
		_rows = t if t is Dictionary else {"_": []}
	var f: Array = _rows.get(str(row), [])
	if f.size() < 6 or int(f[0]) <= 0:
		return null
	return {"images": int(f[0]), "ms": int(f[1]), "buildup": int(f[2]), "rgb": [int(f[3]), int(f[4]), int(f[5])]}


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_mi.material_override = m
	add_child(_mi)


func _process(delta: float) -> void:
	if not is_instance_valid(_frame):
		queue_free()
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait > 0.0:
			return
		delta = -_wait                                     # the part of this frame after the start
	_t += delta
	var to_frame := _frame.global_transform.affine_inverse()
	var alive := false
	for i in _points.size():
		var pairs: Array = _pairs[i]
		for q in pairs:
			q[3] += delta * AGE_RATE
		while not pairs.is_empty() and float(pairs[0][2]) + float(pairs[0][3]) >= 1.0:
			pairs.pop_front()                               # faded out
		var p: Array = _points[i]
		var held: Variant = p[0]
		var w: Node3D = held as Node3D if is_instance_valid(held) else null   # (a weapon freed mid-swing: a
		if _t <= _span and w != null and w.is_visible_in_tree():               # companion gone, a weapon swap)
			var base := to_frame * (w.global_transform * (p[1] as Vector3))
			var tip := to_frame * (w.global_transform * (p[2] as Vector3))
			var last_tip: Vector3 = pairs[-1][1] if not pairs.is_empty() else Vector3.INF
			if pairs.is_empty() or (_frame.global_transform.basis * (tip - last_tip)).length() >= STEP:
				var fade := 0.0                              # the trail's own fade in / out (the new pair's V)
				if _t < 0.2:
					fade = (0.2 - _t) * 5.0
				elif _t > _span - 0.1:
					fade = (_t - (_span - 0.1)) * 5.0
				pairs.append([base, tip, clampf(fade, 0.0, 1.0), 0.0])
				if pairs.size() > MAX_PAIRS:
					pairs.pop_front()
		alive = alive or not pairs.is_empty() or _t <= _span
	_rebuild()
	if not alive:
		queue_free()


## The ribbons, rebuilt each frame in world space from the skeleton's frame.
func _rebuild() -> void:
	_mesh.clear_surfaces()
	var tf := _frame.global_transform
	for pairs in _pairs:
		if pairs.size() < 2:
			continue
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for q in pairs:
			var a := ALPHA * (1.0 - clampf(float(q[2]) + float(q[3]), 0.0, 1.0))
			_mesh.surface_set_color(Color(_color, a * BASE_ALPHA))
			_mesh.surface_add_vertex(tf * (q[0] as Vector3))
			_mesh.surface_set_color(Color(_color, a))
			_mesh.surface_add_vertex(tf * (q[1] as Vector3))
		_mesh.surface_end()
