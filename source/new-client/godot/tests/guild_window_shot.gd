extends Control
## Debug (owner 2026-10-17: the guild UI): the guild window alone with a sample page of the server's roster lines
## (guild.cs SendSocialWindowData format), a member selected - user://guild_window.png. Runs once.
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.2, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var holder := Control.new()
	holder.scale = Vector2(2, 2)
	add_child(holder)
	Server.active = true
	if Server.classes.is_empty():
		Server.classes = JSON.parse_string(FileAccess.get_file_as_string("res://content/rules/server_classes.json"))
	Server.info["guild"] = "Knights of Mularn"
	var w := GuildWindow.new()
	w.resizable = true
	w.patch = [6, 19, 13, 33]
	w.min_size = GuildWindow.BODY
	w.max_size = GuildWindow.BODY
	w.size = GuildWindow.BODY
	w.setup("guild_test", "interact", Rect2(), Vector2(20, 20))
	holder.add_child(w)
	w.build()
	w.receive(["TE", "1", "23", "10"])
	var rows := [["Olred", 50, 26, 0, 2, "Mularn", "Guild leader"], ["Ivareulf", 47, 34, 1, 2, "Vale of Mularn", ""],
		["Yrerid", 46, 28, 2, 1, "Svasud Faste", "healer"], ["Leofoalfrey", 44, 31, 3, 1, "Myrkwood Forest", "gamebot"],
		["Astrungerd", 39, 22, 5, 2, "Jordheim", ""], ["Gjalpinulva", 35, 30, 5, 0, "2 days ago", "alt of Olred"],
		["Livunildtrid", 31, 32, 7, 1, "Gotar", "crafter"], ["Arnaunrik", 28, 29, 8, 0, "5 hours ago", ""],
		["Hrothgarm", 22, 23, 9, 1, "Vale of Mularn", ""], ["Thyrvalda", 12, 38, 9, 0, "1 week ago", "new recruit"]]
	var i := 0
	for r in rows:
		i += 1
		w.receive(["E", str(i), "23", r[0], str(r[1]), str(r[2]), str(r[3]), str(r[4]), r[5], r[6]])
	w.selected = "Yrerid"
	w._rebuild()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://guild_window.png")
	get_tree().quit()
