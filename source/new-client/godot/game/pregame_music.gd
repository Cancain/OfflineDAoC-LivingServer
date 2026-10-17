extends Node
## Autoload "PregameMusic": the client's title music (cc_mp3s.csv 1 mp3_Title = title.mp3, hard-coded in the client)
## playing through login, loading and (later) character select, like the old client. It fades out as the world
## appears, where the zone's own entry music takes over. Volume follows the Esc-menu Music / Volume sliders.

const TITLE_MP3 := "res://content/sounds/files/title.mp3"

var _player: AudioStreamPlayer


func _ready() -> void:
	ZoneAudio.ensure_buses()
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)


func play() -> void:
	if _player.playing:
		return
	_apply_volumes()
	var data := FileAccess.get_file_as_bytes(TITLE_MP3)
	if data.is_empty():
		push_warning("title music missing: run pipeline/build_ui.py")
		return
	var st := AudioStreamMP3.new()
	st.data = data
	st.loop = true
	_player.stream = st
	_player.volume_db = 0.0
	_player.play()


func fade_out(seconds := 2.0) -> void:
	if not _player.playing:
		return
	var tw := create_tween()
	tw.tween_property(_player, "volume_db", -60.0, seconds)
	tw.tween_callback(_player.stop)


func _apply_volumes() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	for bus in ["Master", "Music"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(cfg.get_value("audio", bus.to_lower(), 100)) / 100.0, 0.0001)))
