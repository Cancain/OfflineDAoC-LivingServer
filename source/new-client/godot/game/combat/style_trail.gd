class_name StyleTrail
extends Node3D
## The colour flash of a combat style (owner 2026-10-10): the client's styles.csv gives each style a trail - Imagenum
## afterimages of the weapon, laid down over the style swing from Buildup ms to Duration ms (the swing's length),
## tinted Red / Green / Blue (the five colours 1H / 2H / chains use: red, blue, yellow, green, purple). Each afterimage
## is a glowing copy of the weapon's meshes frozen where the weapon was, fading out, so the swing leaves a coloured
## streak. pipeline/build_classes.py style_trail / patch_style_trails.py put the columns in styles.json.

const FADE := 0.28                           # seconds an afterimage takes to fade
const PEAK := 0.55                           # its starting opacity

var _weapons: Array = []                     # the weapon nodes followed (Node3D)
var _color := Color.WHITE
var _left := 0
var _every := 0.1
var _wait := 0.0
var _ghosts: Array = []                      # [MeshInstance3D, age]
var _mat: StandardMaterial3D


## Starts a trail on these weapon nodes (the held weapons' scenes) for one style; parented to the world so the
## afterimages stay where the weapon was.
static func play(world: Node, weapons: Array, trail: Variant) -> void:
	if not (trail is Dictionary) or weapons.is_empty() or int(trail.get("images", 0)) <= 0:
		return
	var rgb: Array = trail.get("rgb", [255, 255, 255])
	var t := StyleTrail.new()
	t._weapons = weapons.filter(func(w): return is_instance_valid(w))
	t._color = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	t._left = int(trail.images)
	var span := maxf(0.05, (float(trail.get("ms", 1000)) - float(trail.get("buildup", 400))) / 1000.0)
	t._every = span / float(t._left)
	t._wait = float(trail.get("buildup", 400)) / 1000.0
	world.add_child(t)


## The weapons in a model's hands (the bone attachments on the Held / Hand bones - not the belt, back or shield).
static func held(model: Node) -> Array:
	var out: Array = []
	if model == null or not is_instance_valid(model):
		return out
	for a in model.find_children("*", "BoneAttachment3D", true, false):
		var bone := String((a as BoneAttachment3D).bone_name)
		if bone in ["Bip01 R Held", "Bip01 L Held", "Bip01 R Hand"]:
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


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = false
	_mat.albedo_color = Color(_color, PEAK)


func _process(delta: float) -> void:
	_wait -= delta
	while _left > 0 and _wait <= 0.0:
		_left -= 1
		_wait += _every
		_snapshot()
	for g in _ghosts:
		g[1] += delta
		var a := PEAK * (1.0 - clampf(g[1] / FADE, 0.0, 1.0))
		((g[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = a
	while not _ghosts.is_empty() and _ghosts[0][1] >= FADE:
		(_ghosts.pop_front()[0] as Node).queue_free()
	if _left <= 0 and _ghosts.is_empty():
		queue_free()


## One afterimage: every mesh of the followed weapons copied where it is now.
func _snapshot() -> void:
	for w in _weapons:
		if not is_instance_valid(w) or not (w as Node3D).is_visible_in_tree():
			continue
		for src in (w as Node).find_children("*", "MeshInstance3D", true, false):
			var m := src as MeshInstance3D
			if m.mesh == null or not m.visible:
				continue
			var g := MeshInstance3D.new()
			g.mesh = m.mesh
			g.material_override = _mat.duplicate()
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(g)
			g.global_transform = m.global_transform
			_ghosts.append([g, 0.0])
