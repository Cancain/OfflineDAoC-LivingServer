extends Node
## Debug (owner 2026-10-10: mini group window, GROUP page, BENEFITS, war map): fills a pretend group of three (test
## only - nothing adds members in the game yet) and takes pictures of each window; then the war map's three pages.
##   --screen 1 --skip-login --zone=0 --probe=group_ui_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(v.args.get("out", "user://"))
	var buff := [{"icon": 10, "border": 0, "name": "strength"}, {"icon": 20, "border": 0, "name": "dexterity"}]
	PlayerData.group = [
		{"name": "Briaorlin", "class_name": "Cleric", "level": 20, "hp": 0.8, "hp_pts": 240, "power": 0.6, "power_pts": 90, "end": 1.0, "effects": buff},
		{"name": "Tadinvan", "class_name": "Armsman", "level": 21, "hp": 0.35, "hp_pts": 120, "power": 0.0, "power_pts": 0, "end": 0.5, "effects": buff.slice(0, 1)},
		{"name": "Eogoron", "class_name": "Wizard", "level": 19, "hp": 1.0, "hp_pts": 150, "power": 0.15, "power_pts": 30, "end": 1.0, "effects": []}]
	PlayerData.group_changed.emit()
	var ui = v.ui
	ui.windows["minigroup"].show_window()
	ui.windows["benefits"].show_window()
	ui.show_sheet("group")
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/group_windows.png")
	ui.windows["benefits"].hide_window()
	ui.windows["warmap"].show_window()
	for r in ["alb", "mid", "hib"]:
		ui.warmap.show_realm(r)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/warmap_%s.png" % [out, r])
	PlayerData.disband_requested.emit()
	get_tree().quit()
