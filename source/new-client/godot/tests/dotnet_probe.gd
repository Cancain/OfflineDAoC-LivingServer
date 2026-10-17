extends SceneTree
## Check (bot plan phase 3): the game's C# assembly loads under the Godot .NET build.
##   tools\godot_net\Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot -s res://tests/dotnet_probe.gd
func _initialize() -> void:
	var s = load("res://game/world_host/HostInfo.cs")
	if s == null:
		print("[dotnet] FAIL: HostInfo.cs did not load")
	else:
		var info = s.new()
		print("[dotnet] ", info.call("Hello"))
		for r in ["alb", "mid", "hib"]:
			var c: Dictionary = info.call("MakeBot", r, 1650)
			print("[dotnet] bot made by C# through CharacterFactory: %s the %s %s (%s), start %s" % [c.name, c.race,
					c.class_name, c.prefix, c.start.get("zone_name", "?")])
	quit()
