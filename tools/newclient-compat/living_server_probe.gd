extends SceneTree
## Living Server messages in the new client (test harness, not part of the game): connects the real network client
## (DaocClient.cs) to a stand-in server that sends the Living Server's chat lines and yes / no boxes through the game
## server's own packet code, passes every decoded packet to the game's own ServerWorld._message / _dialog, with the
## real GameUI built, then writes what the client showed: user://living_server_probe.json.
##   Godot --headless --path godot -s res://tests/living_server_probe.gd

var emitted: Array = []          # [text, kind] from PlayerData.message (what the chat boxes are given)
var packets: Array = []          # decoded "message" / "dialog" packets
var done := false
var boxes_seen: Array = []   # the text in each yes / no box when ACCEPT was clicked
var ui
var sw


func _initialize() -> void:
	await process_frame
	load("res://game/ui/ui_art.gd").settings_path = "user://settings_probe.cfg"
	root.get_node("PlayerData").message.connect(func(t, k): emitted.append([t, k]))
	ui = load("res://game/ui/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	await process_frame
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar ui\nvar player\n"
	stub.reload()
	var viewer := Node.new()
	viewer.set_script(stub)
	viewer.set("ui", ui)
	root.add_child(viewer)
	sw = load("res://game/net/server_world.gd").new()
	sw.viewer = viewer
	var client = load("res://game/net/DaocClient.cs").new()
	root.add_child(client)
	root.get_node("Server").client = client
	client.World.connect(_on_world)
	client.Disconnected.connect(func(why): print("[probe] disconnected: ", why); done = true)
	print("[probe] connecting")
	client.Open("127.0.0.1")
	var waited := 0.0
	while not done and waited < 40.0:
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(1.0).timeout
	_report()
	quit(0)


func _on_world(kind: String, d: Dictionary) -> void:
	if kind == "message":
		packets.append({"kind": "message", "type": int(d.type), "chat": bool(d.chat), "popup": bool(d.popup), "text": String(d.text)})
		sw._message(d)
	elif kind == "dialog":
		packets.append({"kind": "dialog", "type": int(d.type), "code": int(d.code), "text": String(d.text),
				"data1": int(d.data1), "data2": int(d.data2)})
		sw._dialog(d)
		_answer_boxes()


## Click ACCEPT on every yes / no box the server opened, as a player would.
func _answer_boxes() -> void:
	await create_timer(0.3).timeout
	for b in ui.root.find_children("*", "Button", true, false):
		if (b as Button).text == "ACCEPT" and is_instance_valid(b) and not b.is_queued_for_deletion():
			var box_text := ""
			for l in (b as Node).get_parent().find_children("*", "Label", true, false):
				box_text += (l as Label).text + " "
			boxes_seen.append(box_text.strip_edges())
			print("[probe] clicking ACCEPT on: ", box_text.strip_edges())
			(b as Button).pressed.emit()


func _report() -> void:
	var chat_text := ""
	if ui.chat and ui.chat.get("_log"):
		chat_text = (ui.chat.get("_log") as RichTextLabel).get_parsed_text()
	var system_text := ""
	if ui.chat_combat and ui.chat_combat.get("_log"):
		system_text = (ui.chat_combat.get("_log") as RichTextLabel).get_parsed_text()
	var centre: Array = []
	if ui._center_box and is_instance_valid(ui._center_box):
		for c in ui._center_box.get_children():
			if c is Label:
				centre.append((c as Label).text)
	var out := {"packets": packets, "emitted": emitted, "chat_main_types": ui.chat.get("types") if ui.chat else [],
			"chat_main": chat_text, "chat_system_box": system_text, "centre": centre, "boxes_accepted": boxes_seen}
	var f := FileAccess.open("user://living_server_probe.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[probe] wrote ", ProjectSettings.globalize_path("user://living_server_probe.json"), ": ", packets.size(), " packets, ",
			emitted.size(), " chat lines")
