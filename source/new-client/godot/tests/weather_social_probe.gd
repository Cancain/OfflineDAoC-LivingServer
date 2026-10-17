extends Node
## Debug (owner 2026-10-14: the server's weather, the friends list, the social lines): on a test server run with
## Claude's GM test character in Lough Derg - a storm started over you (/weather start), the sky's storm following it,
## then stopped; /friend window and /news as lists in the information window (no raw "N,..." lines in chat).
var v: Node
var _chat: Array = []


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): _chat.append(String(t)))
	await _wait(8.0)
	Server.command("/jump to 335142 516409 4791 200")
	await _wait(14.0)
	v = get_tree().current_scene
	var wz := int(v.region.current.info.id) if v.region and v.region.current else int(v.zone.info.id)
	var rx: float = Server.to_region(wz, v.player.global_position).x
	print("[weather] at region x ", rx, "  weather before: ", Server.weather, "  sky storm ", v.sky.storm)
	Server.command("/weather start %d 40000 20 16000 100" % int(rx + 15000))
	await _wait(1.5)
	print("[weather] after /weather start: ", Server.weather, "  storm here ", Server.storm_at(rx))
	await _wait(12.0)
	print("[weather] 12 s later: sky storm_target ", v.sky.storm_target, "  storm ", snappedf(v.sky.storm, 0.01))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://weather_1.png")
	Server.command("/weather stop")
	await _wait(3.0)
	print("[weather] after /weather stop: ", Server.weather, "  storm_target ", v.sky.storm_target)
	# --- friends and news
	print("[friends] online at login: ", Server.friends_online)
	_chat.clear()
	Server.command("/friend window")
	await _wait(1.5)
	var w: ClassicWindow = v.ui.windows.info
	print("[friends] info window: ", w.visible, " '", (w.get_node("Title") as Label).text, "': ",
			(w.get_node("Body") as RichTextLabel).text.left(200).replace("\n", " | "))
	Server.command("/news")
	await _wait(1.5)
	print("[news] info window: '", (w.get_node("Title") as Label).text, "': ",
			(w.get_node("Body") as RichTextLabel).text.left(300).replace("\n", " | "))
	print("[news] raw social lines in chat: ", _chat.filter(func(t): return t.begins_with("N,") or t.begins_with("F,") or t == "TF"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://weather_2.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
