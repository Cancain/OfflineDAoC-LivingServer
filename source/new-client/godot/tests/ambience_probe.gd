extends Node
## Debug (owner 2026-10-10: Muspelheim's lava / explosions were silent): stand at --pos for --secs (default 60) and log
## the zone's ambience - loops playing and one-shots fired, by sound.
##   --headless --skip-login --zone=104 --pos=x,y,z --figure=cel_m --probe=ambience_probe
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var audio: ZoneAudio = v.audio
	var fired := {}
	var loops := {}
	var secs := int(v.args.get("secs", "60"))
	for t in secs * 4:
		await get_tree().create_timer(0.25).timeout
		for c in audio.get_children():
			if c is AudioStreamPlayer and c.playing and c.stream:
				var f := String(c.stream.resource_path if c.stream.resource_path != "" else str(c.get_instance_id()))
				var key := String(c.get_meta("snd", f))
				if (c.stream as AudioStreamWAV) and (c.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
					loops[key] = true
				else:
					fired[key] = true
	print("[amb] regions inside: ", audio._regions.filter(func(r): return r["fade"] > 0.5).map(func(r): return r["def"]["section"]))
	var seen := {}
	for r in audio._regions:
		for snd in r["sounds"]:
			var s: Dictionary = snd["def"]
			var n := String(s.get("name", str(s.get("id"))))
			if snd["player"] != null or snd["gain"] > 0.0:
				seen[n] = true
	print("[amb] stats: ", audio.stats)
	print("[amb] loops now: ", seen.keys())
	print("[amb] loops heard: ", loops.keys(), "
[amb] one-shots heard: ", fired.keys())
	get_tree().quit()
