extends Node
## Debug (owner 2026-10-10: pray / level up / bind effects + sounds): plays each emote overlay on the player and saves
## a picture of it.
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=emote_fx_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(v.args.get("out", "user://"))
	v.player.cam_distance = 4.5
	v.player.cam_pitch = -0.35
	for pair in [["pray", 8005, 0.8], ["levelup", 8007, 1.2], ["bind_hib", 8009, 1.2]]:
		var snd: CharacterSounds = v.player.sounds
		var before := snd.play_log.size() if snd else 0
		SpellFx.emote(int(pair[1]), v.player, snd)
		await get_tree().create_timer(float(pair[2])).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/emote_%s.png" % [out, pair[0]])
		print("[emote] ", pair[0], " sounds: ", snd.play_log.slice(before) if snd else "no CharacterSounds")
		await get_tree().create_timer(3.5).timeout
	get_tree().quit()
