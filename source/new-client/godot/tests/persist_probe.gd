extends Node
## Headless check: window positions survive an Options change and a "re-enter"; per-character key toggle; bank kept.
func _ready() -> void:
	UiArt.settings_path = "user://settings_persisttest.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(UiArt.settings_path))
	var c := {"name": "Persist", "realm": "hib", "prefix": "cel_m", "base": "CELT-ARMS", "class_name": "Guardian"}
	PlayerData.load_character(c)
	var ui := GameUI.new()
	add_child(ui)
	await get_tree().process_frame
	var w: ClassicWindow = ui.windows["chat_combat"]
	w.position = Vector2(200, 150)
	w.save_position()
	ui.options._save("audio", "master", 55.0)              # used to write back a stale copy over the position
	ui.quickbars[0].set_bank(4)
	ui.queue_free()
	await get_tree().process_frame
	var ui2 := GameUI.new()
	add_child(ui2)
	await get_tree().process_frame
	print("combat chat after re-enter: ", ui2.windows["chat_combat"].position, " (expected (200, 150))")
	print("bank after re-enter: ", PlayerData.quickbar_bank[0] + 1, " (expected 5)")
	var shared := String(Keybinds.bindings["jump"][0]) if Keybinds.bindings["jump"].size() > 0 else "-"
	Keybinds.set_character_specific(true)
	Keybinds.bind("jump", 0, "J")
	print("own keys on: path ", Keybinds.path, " jump=", Keybinds.bindings["jump"])
	Keybinds.set_character_specific(false)
	print("own keys off: path ", Keybinds.path, " jump=", Keybinds.bindings["jump"], " (shared was ", shared, ")")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(UiArt.settings_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://keybinds/local_persist.cfg"))
	get_tree().quit()
