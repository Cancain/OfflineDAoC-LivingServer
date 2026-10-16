extends SceneTree
## Compiles scripts with the autoloads present (--check-only can't see them):
##   --headless --path godot -s res://tests/load_check.gd -- res://game/a.gd res://game/b.gd


func _initialize() -> void:
	await process_frame
	var bad := 0
	for p in OS.get_cmdline_user_args():
		var s = load(p)
		if s == null or not (s as Script).can_instantiate():
			print("[load_check] FAIL ", p)
			bad += 1
		else:
			print("[load_check] ok ", p)
	quit(bad)
