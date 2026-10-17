extends Node
## Debug: loads the scripts given (--scripts=a.gd,b.gd) with the game's autoloads present - a parse error shows here
## instead of as a grey window (scripts checked alone miss the autoload names).
##   Godot --headless --path godot res://tests/compile_check.tscn -- --scripts=res://game/x.gd,res://game/y.gd


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scripts="):
			for path in a.get_slice("=", 1).split(","):
				var s := load(path) as Script
				print("[check] ", path, " ", "OK" if s and s.can_instantiate() else "FAILED")
	get_tree().quit()
