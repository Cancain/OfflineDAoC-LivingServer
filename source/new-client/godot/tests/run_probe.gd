extends SceneTree
## Runs a probe node script after the autoloads are up: -- res://tests/<probe>.gd
func _initialize() -> void:
	await process_frame
	var s = load(OS.get_cmdline_user_args()[0])
	root.add_child(s.new())
