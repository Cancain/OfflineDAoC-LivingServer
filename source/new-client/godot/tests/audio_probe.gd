extends Node
## Debug: run the zone audio scheduler through day / night / storm and log which client sounds play per region.
## Runs fine headless (dummy audio driver): godot --headless --path godot -- --zone=200 --probe=audio_probe

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var viewer := get_tree().current_scene
	var audio: ZoneAudio = viewer.audio
	var sky: SkySystem = viewer.sky
	if audio == null or audio.data.is_empty():
		print("AUDIO PROBE: no audio data")
		get_tree().quit(1)
		return
	Engine.time_scale = 8.0                         # roll the random sounds faster
	for case in [["day clear", 10.0, 0.0], ["night clear", 23.0, 0.0], ["day storm", 13.0, 1.0], ["dawn 05:15", 5.25, 0.0], ["day clear, entry music over", 10.0, 0.0]]:
		sky.set_hour(case[1])
		sky.time_scale = 0.0
		sky.storm_forced = case[2]
		sky.storm = case[2]
		audio.stats.clear()
		await get_tree().create_timer(60.0).timeout
		print("== %s (%s, storm %.1f): %s" % [case[0], sky.clock_text(), sky.storm, audio.debug_text()])
		for st in audio._regions:
			var names := []
			for snd in st["sounds"]:
				var pl = snd["player"]
				if pl != null and is_instance_valid(pl) and pl.playing:
					names.append("%d%s" % [int(snd["def"]["id"]), "L" if int(snd["def"]["type"]) == 2 else ""])
			var stat: Dictionary = audio.stats.get(st["def"]["name"], {"played": 0, "full": 0})
			if not names.is_empty() or stat["played"] > 0 or stat["full"] > 0:
				print("   %-48s now: %-22s  last 60 s: played %d, voice limit hit %d" % [st["def"]["name"], " ".join(names), stat["played"], stat["full"]])
	get_tree().quit()
