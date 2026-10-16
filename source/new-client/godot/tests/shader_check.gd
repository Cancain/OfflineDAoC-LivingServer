extends SceneTree
## Compiles NifMaterials' shaders on the GPU (headless runs never compile them): a clamped and a wrapped layer, every
## alpha mode, drawn for a few frames; shader errors land in the output. Quits by itself.
##   Godot --path godot --screen 1 -s res://tests/shader_check.gd

var _frames := 0


func _initialize() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, 4)
	var mats := NifMaterials.new({"original": "res://content/monsters/effects/alb_ecrack1_hit/textures/original"}, "original")
	var x := -3.0
	for alpha in ["opaque", "mask", "blend", "add"]:
		var spec := {"slots": {"base": {"tex": "mud", "uv": 0, "wrap": false}, "glow": {"tex": "hotrim", "uv": 0, "wrap": false},
				"detail": {"tex": "mud", "uv": 0, "wrap": true},
				"env": {"tex": "mud", "uv": 0, "wrap": true}}, "alpha": alpha, "double_sided": true, "tint": [1, 1, 1]}
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = mats.material(spec)
		mi.position = Vector3(x, 0, 0)
		x += 2.0
		root.add_child(mi)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		print("[shader_check] drew %d frames" % _frames)
	return _frames >= 6
