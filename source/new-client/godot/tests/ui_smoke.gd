extends Node
## Headless smoke test of the in-game UI (no zone): a test character (Celt Guardian) with its starter weapon,
## every sheet built once, inventory moves exercised, then quit. Run:
##   Godot --headless --path godot res://tests/ui_smoke.tscn


func _ready() -> void:
	UiArt.settings_path = "user://settings_uitest.cfg"
	var c := {"name": "Smoketest", "realm": "hib", "prefix": "cel_m", "race": "Celt", "base": "CELT-ARMS",
			"class_name": "Guardian", "level": 1}
	PlayerData.load_character(c)
	print("stats ", PlayerData.stats, " class stats ", PlayerData.class_stats)
	print("inventory ", PlayerData.inventory)
	var ui := GameUI.new()
	add_child(ui)
	for tab in GameUI.TABS:
		ui.show_sheet(tab)
		await get_tree().process_frame
		print("sheet ", tab, " children ", ui._sheet_body.get_child_count())
	ui.options.show_window()
	for p in OptionsWindow.PAGES:
		ui.options.show_page(p)
		await get_tree().process_frame
		print("options ", p, " rows ", ui.options._list.get_child_count())
	# inventory: take the weapon off, put it back, try a bad slot
	var w := PlayerData.inventory.keys()
	print("unequip ", PlayerData.unequip(int(w[0])), " -> ", PlayerData.inventory)
	print("equip ", PlayerData.equip(PlayerData.BACKPACK), " -> ", PlayerData.inventory)
	print("bad move ", PlayerData.move(int(PlayerData.inventory.keys()[0]), 21))
	print("icon ", ItemDb.icon(901), " ", ItemDb.icon(1204))
	print("SMOKE OK")
	get_tree().quit()
