extends Node
## Debug (owner 2026-10-14: the level still said 39 after reaching 40; character select showed level 1 for a level 2;
## weapon skill / damage, armor factor, hit points and the additional info on the character sheet): on a test server
## run, Claude's GM test character levels up (/player levelup on yourself) with the character sheet open - every
## place the level shows, the sheet's boxes and additional info (screenshots user://level_<n>.png); then /quit and the
## character screen's level.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k):
		if String(t).contains("level") or String(t).contains("Level"):
			print("[chat] ", t))
	await _wait(8.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	v.ui.show_sheet("character")
	await _wait(1.0)
	_report("before")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://level_1.png")
	Server.client.call("Target", Server.me_oid, 0x6000)
	await _wait(1.0)
	Server.command("/player levelup")
	await _wait(3.0)
	_report("after /player levelup")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://level_2.png")
	var name := String(PlayerData.character.get("name", ""))
	var lvl := PlayerData.level
	var after := Node.new()                                  # outlives the world: the character screen's level
	after.set_script(load("res://tests/level_after_quit.gd"))
	after.set_meta("char_name", name)
	after.set_meta("world_level", lvl)
	get_tree().root.add_child(after)
	v.ui.chat.run_line("/quit")


func _report(when: String) -> void:
	var body: Control = v.ui._sheet_body
	var texts := []
	for c in body.get_children():
		if c is Label and (c as Label).text != "":
			texts.append((c as Label).text)
	var info := ""
	for c in body.get_children():
		if c is RichTextLabel:
			info = (c as RichTextLabel).get_parsed_text().replace("\n", " | ")
	print("[level] %s: PlayerData.level %d  server level %s  realm points %d  spec points %s" % [when, PlayerData.level,
			Server.info.get("level", "?"), PlayerData.realm_points, PlayerData.character.get("spec_points", "?")])
	print("[level]   sheet boxes: ", texts)
	print("[level]   additional info: ", info.left(400))
	print("[level]   weapon stats: ", Server.weapon_stats, "  max hp ", Server.max_hp)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
