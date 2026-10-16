extends Node
## Debug: the owner-mapped Lough Derg lake loop (176 -> s_Lake_Loop) fades in inside a "lakes" circle, out outside.

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var viewer := get_tree().current_scene
	var audio: ZoneAudio = viewer.audio
	var p: Player = viewer.player
	for at in [["Mag Mell (outside)", Vector2(25900, 7700)], ["lake circle 03 centre", Vector2(38912, 20992)]]:
		var y := maxf(viewer.zone.height_at(at[1].x * 0.025, at[1].y * 0.025), viewer.zone.water_level_at(at[1].x * 0.025, at[1].y * 0.025) - 1.2)
		p.global_position = Vector3(at[1].x * 0.025, y + 0.3, at[1].y * 0.025)
		await get_tree().create_timer(8.0).timeout
		for st in audio._regions:
			if st["def"]["name"] == "lakes":
				var snd: Dictionary = st["sounds"][0]
				var pl = snd["player"]
				print("%s: lakes fade %.2f, loop gain %.2f, playing %s %s" % [at[0], st["fade"], snd["gain"],
					pl != null and is_instance_valid(pl) and pl.playing, pl.stream.resource_path if pl else ""])
	get_tree().quit()
