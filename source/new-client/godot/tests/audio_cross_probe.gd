extends Node
## Debug (owner 2026-10-14: crossing a zone line restarts the music): in Valley of Bri Leith the player steps west over
## the line into Lough Derg (the seamless region crossing, no loading screen) - the entry music before and after (the
## same player, still playing, its position going on), the old zone's sounds fading out, the new zone's coming in.
##   --skip-login --zone=206 --figure=cel_m --probe=audio_cross_probe
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(3.0)
	var a: ZoneAudio = v.audio
	var mp3: AudioStreamPlayer = a._mp3
	print("[audio] in %s: entry music %d playing %s at %.1f s  (%s)" % [v.zone.info.name, a._mp3_id, mp3.playing,
			mp3.get_playback_position(), a.debug_text()])
	var p: Vector3 = v.player.global_position
	v.player.global_position = Vector3(25.0, v.zone.height_at(25.0, p.z) + 1.0, p.z)   # near the line: the neighbour
	var nid: int = v.region.zone_id_at(-5.0, p.z)                                       # streams in first
	for _i in 200:
		if v.region.zones.has(nid):
			break
		await _wait(0.1)
	print("[audio] neighbour %d loaded: %s" % [nid, v.region.zones.has(nid)])
	await _wait(1.0)
	if not mp3.playing:                                         # (the 23 s track ended while the neighbour loaded:
		a.play_mp3(a._mp3_id)                                   # play it again, to cross while it plays)
		await _wait(2.0)
	print("[audio] just before the line: music playing %s at %.1f s" % [mp3.playing, mp3.get_playback_position()])
	v.player.global_position = Vector3(-6.0, v.zone.height_at(0.0, p.z) + 1.0, p.z)
	var t0 := Time.get_ticks_msec()
	while v.audio == a and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	var b: ZoneAudio = v.audio
	if b == a:
		print("[audio] no crossing in 10 s (zone %s)" % v.zone.info.name)
		get_tree().quit()
		return
	print("[audio] crossed into %s after %d ms: entry music %d, the same player %s, playing %s at %.1f s" % [
			v.zone.info.name, Time.get_ticks_msec() - t0, b._mp3_id, b._mp3 == mp3, b._mp3.playing,
			b._mp3.get_playback_position()])
	print("[audio]   old zone audio fading out: ", is_instance_valid(a) and v.get_node_or_null("ZoneAudioOld") != null)
	await _wait(3.0)
	print("[audio]   3 s on: old zone audio gone %s, music at %.1f s, %s" % [not is_instance_valid(a),
			b._mp3.get_playback_position(), b.debug_text()])
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
