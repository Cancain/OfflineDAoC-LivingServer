extends Node
## Debug (level_probe): left under the root before /quit so it outlives the world - the character screen's level for
## the character (meta "char_name", "world_level") at 1, 3 and 6 s, then the test window closes.


func _ready() -> void:
	var name := String(get_meta("char_name", ""))
	var lvl := int(get_meta("world_level", 0))
	for t in [1.0, 2.0, 3.0]:
		await get_tree().create_timer(t).timeout
		var found := "-"
		for r in ["alb", "mid", "hib"]:
			for c in Server.characters_in(r):
				if String(c.name) == name:
					found = str(c.level)
		var scene := get_tree().current_scene
		print("[level] character screen: %s level %s (in the world: %d)  scene %s" % [name, found, lvl,
				scene.scene_file_path if scene else "-"])
	get_tree().quit()
