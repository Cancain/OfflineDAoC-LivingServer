extends Node
## Debug: the trainer window with the server's lists made up (no server) - a Sluaghbinder's specs and its 30 realm
## abilities (some trained, some not yet available) - and a quickbar slot on its reuse timer. user://trainer_shot.png
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=trainer_shot
const RAS := ["Augmented Strength", "Mastery of Arms", "Augmented Dexterity", "Mastery of Pain", "Mastery of Blocking",
		"Hail of Blows", "Augmented Constitution", "Second Wind", "Augmented Quickness", "Augmented Acuity", "Serenity",
		"Wild Arcana", "Long Wind", "Tireless", "Regeneration", "Toughness", "Determination", "Mastery of Water",
		"Avoidance of Magic", "Lifter", "Veil Recovery", "First Aid", "Ignore Pain", "Rain of Fire", "Rain of Ice",
		"Rain of Annihilation", "The Empty Mind", "Purge", "Wild Minion", "Crippling Plague"]


func _ready() -> void:
	var viewer := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var ui = viewer.ui
	Server.active = true
	Server.skills = [{"page": 0, "name": "Bane", "level": 30, "bonus": 0, "icon": 0},
			{"page": 0, "name": "Nauberite", "level": 22, "bonus": 3, "icon": 0},
			{"page": 6, "name": "Crippling Plague", "level": 1, "icon": 3425}]
	Server.realm_abilities = []
	for i in RAS.size():
		Server.realm_abilities.append({"index": i, "level": 1 if i in [0, 29] else 0, "cost": [1, 3, 6, 10, 14][i % 5],
				"name": RAS[i], "available": i % 7 != 3})
	Server.ra_points = 14
	var e := {"kind": "ability", "id": "srv:skill:0", "icon": 0, "border": -1, "name": "Crippling Plague"}
	PlayerData.quickbars[0][PlayerData.quickbar_bank[0]][0] = e
	Server._refresh_bar_icons()
	Server.disabled["srv:skill:0"] = Time.get_ticks_msec() + 47000
	PlayerData.changed.emit()
	ui.trainer.open()
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://trainer_shot.png")
	print("[trainer] icon ", e.icon, " border ", e.border)
	get_tree().quit()
