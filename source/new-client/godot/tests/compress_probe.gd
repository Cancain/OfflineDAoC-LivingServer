extends SceneTree
## Debug: Bip01's position in a cast clip from the glTF as loaded, then after Animation.compress() (tools/pack_scenes.gd)
## - does compression move the root? (owner 2026-10-11: a troll's feet lifted when he cast)
##   Godot --headless --path godot -s res://tests/compress_probe.gd -- tro_m cast_bk_hand_start


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "tro_m"
	var clip: String = args[1] if args.size() > 1 else "cast_bk_hand_start"
	var dir := "res://content/characters/races/%s" % prefix
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.base_path = ProjectSettings.globalize_path(dir)
	doc.append_from_file(dir + "/figure.gltf", state)
	var root := doc.generate_scene(state)
	var ap := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var a := ap.get_animation(clip)
	var tr := -1
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			tr = t
	var raw := []
	for k in 9:
		raw.append(a.position_track_interpolate(tr, a.length * k / 8.0).snapped(Vector3.ONE * 0.01))
	print("[cmp] raw        ", raw)
	for cfg in [[8192, 120, 4.0], [8192, 30, 4.0], [8192, 60, 0.0], [4096, 30, 0.0], [16384, 15, 4.0]]:
		var c2 := a.duplicate(true) as Animation
		c2.compress(cfg[0], cfg[1], cfg[2])
		var cmp := []
		for k in 9:
			cmp.append(c2.position_track_interpolate(tr, a.length * k / 8.0).snapped(Vector3.ONE * 0.01))
		print("[cmp] ", cfg, " ", cmp)
	root.free()
	quit()
