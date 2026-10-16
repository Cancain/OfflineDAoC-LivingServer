extends Node
## Debug: the Realm Exchange window with made-up rows (no server): browse, my listings and the price box, each
## saved as a screenshot (user://exchange_*.png). Windowed, on the Acer:
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=exchange_shot
func _ready() -> void:
	var viewer := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var ui = viewer.ui
	var names := ["Bloodied Chain Hauberk", "Rune Carved Staff", "Silvered Studded Gloves", "Pristine Cloak of the Wild",
			"Glowing Arcanium Ring", "Heavy Mithril Greaves", "Wyvern Fang Spear", "Cured Leather Jerkin"]
	var models := [2236, 1170, 2254, 1722, 103, 1201, 1004, 2195]
	Server.market_items = []
	for i in 14:
		var id := "srvx:%d" % i
		ItemDb.add_runtime(id, {"id": id, "name": names[i % names.size()], "level": 8 + i * 3, "quality": 85 + i % 15,
				"model": models[i % models.size()], "icon": Server.item_icon(models[i % models.size()]),
				"price": (i + 1) * 13575 + i * 1000000, "can_use": i % 5 != 3, "detail_key": "x:%d" % i, "object_type": 34})
		Server.market_items.append(id)
	Server.market_page = 0
	Server.market_pages = 3
	Server.market_count = 74
	Server.proceeds = 3 * 10000 + 45 * 100
	ui.exchange.open_tab("browse")
	ui.exchange.select_row(2)
	await get_tree().create_timer(1.0).timeout
	_shot("browse")
	Server.listings = {}
	for i in 5:
		var s: int = Server.CHEST_FIRST + i
		var id := "srvc:%d" % s
		ItemDb.add_runtime(id, {"id": id, "name": names[(i + 3) % names.size()], "level": 20 + i, "quality": 94,
				"model": models[(i + 3) % models.size()], "icon": Server.item_icon(models[(i + 3) % models.size()]),
				"detail_key": s, "object_type": 34})
		Server.listings[s] = id
	ui.exchange.show_tab("listings")
	await get_tree().create_timer(1.0).timeout
	_shot("listings")
	ui.exchange.ask_price(Server.CHEST_FIRST + 1)
	await get_tree().create_timer(1.0).timeout
	_shot("price")
	get_tree().quit()


func _shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://exchange_%s.png" % tag)
	print("[shot] ", ProjectSettings.globalize_path("user://exchange_%s.png" % tag))
