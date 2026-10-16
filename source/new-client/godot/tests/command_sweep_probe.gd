extends Node
## Debug (owner 2026-10-14: "do a check of all server commands and make sure they reach the client and function
## properly"; /sit and the Sit key; /quit; GM /jump): on the running server with Claude's GM test character, every
## safe command typed into the chat window one at a time - what came back (the server's first line, the world packets
## by kind, any packet the client doesn't read), then the Sit key, /sit /stand, /jump, and /quit last (a GM quits at
## once: saved, then the character screen).
var v: Node
var _lines: Array = []
var _kinds := {}

const COMMANDS := ["/who", "/played", "/stats", "/time", "/region", "/realm", "/relics", "/gloc", "/faceloc 10000 10000",
	"/afk testing", "/afk", "/anonymous", "/anonymous", "/roll 100", "/random 100", "/serverinfo", "/version", "/online",
	"/news", "/servernews", "/classes", "/combatstats", "/xpstats", "/xp", "/filter", "/held", "/helm", "/helm", "/cloak",
	"/cloak", "/hood", "/hood", "/spacing", "/group", "/lfg", "/friend", "/ignore", "/range", "/gtrange", "/autoloot",
	"/autosplit", "/where", "/targetstats", "/targeteffects", "/checkconcolor", "/sprint", "/sprint", "/assist", "/mobs",
	"/lookfar", "/task", "/quest", "/questguide", "/realmtask", "/realmtimer", "/emote waves", "/wave", "/bow", "/dance",
	"/say hello", "/gu hello", "/cmdhelp", "/settitle", "/statsanon", "/statsanon", "/channel", "/chat", "/battlechat",
	"/loc", "/stick", "/follow", "/face", "/qbar 2", "/qbar 1", "/rw", "/rw", "/GMinfo", "/heal", "/fly", "/fly",
	"/gmstealth", "/gmstealth", "/weather"]


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): _lines.append(String(t)))
	Server.world.connect(func(kind: String, _d: Dictionary): _kinds[kind] = int(_kinds.get(kind, 0)) + 1)
	await _wait(10.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	var sw: ServerWorld = v.npcs
	# a target for /assist /targetstats /stick ...: the nearest living
	var near: NpcState = null
	for st in sw.by_oid.values():
		var s: NpcState = st
		if s.view and s.alive and (near == null or s.pos.distance_to(v.player.global_position) < near.pos.distance_to(v.player.global_position)):
			near = s
	if near:
		sw.select(near.view)
		await _wait(1.0)
	var raw0: Dictionary = Server.raw_seen.duplicate()
	for c in COMMANDS:
		_lines.clear()
		_kinds.clear()
		var raw_before: Dictionary = Server.raw_seen.duplicate()
		v.ui.chat.run_line(c)
		await _wait(1.2)
		var raw_new := []
		for code in Server.raw_seen:
			if int(Server.raw_seen[code]) > int(raw_before.get(code, 0)):
				raw_new.append("0x%02X" % int(code))
		var k := _kinds.keys().filter(func(x): return x not in ["move", "status", "time", "npc", "remove", "equipment"])
		print("[cmd] %-22s -> %s%s%s" % [c, (_lines[0].left(90) if _lines.size() > 0 else "(no line)"),
				("  +" + str(_lines.size() - 1) + " lines" if _lines.size() > 1 else ""),
				("  packets " + str(k) if not k.is_empty() else "") + ("  UNREAD " + str(raw_new) if not raw_new.is_empty() else "")])
		if c in ["/stick", "/follow", "/face"]:
			print("[cmd]      tracking: ", v.player.track_mode)
	v.player.stop_track(true)
	# --- sitting: /sit, /stand, the Sit key, moving
	await _wait(1.0)
	v.ui.chat.run_line("/sit")
	await _wait(2.0)
	print("[sit] after /sit: sitting ", v.player.sitting)
	v.ui.chat.run_line("/stand")
	await _wait(2.0)
	print("[sit] after /stand: sitting ", v.player.sitting)
	var binds: Array = Keybinds._held.get("sit", [])
	if binds.size() > 0:
		var ev := InputEventKey.new()
		ev.keycode = binds[0].key
		ev.physical_keycode = binds[0].key
		ev.pressed = true
		Input.parse_input_event(ev)
		await _wait(0.1)
		var up := ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await _wait(2.5)
		print("[sit] after the Sit key (", OS.get_keycode_string(binds[0].key), "): sitting ", v.player.sitting)
		Input.parse_input_event(ev)
		await _wait(0.1)
		Input.parse_input_event(up)
		await _wait(2.5)
		print("[sit] after the Sit key again: sitting ", v.player.sitting)
	# --- GM /jump
	var before: Vector3 = v.player.global_position
	v.ui.chat.run_line("/jump to 335142 516409 4791 200")
	await _wait(12.0)
	v = get_tree().current_scene
	print("[jump] ", Server.entry, "  now at ", v.player.global_position if v and v.get("player") else "-")
	print("[raw] undecoded packet codes during the sweep: ", Server.raw_seen)
	# --- /quit last
	v.ui.chat.run_line("/quit")
	await _wait(6.0)
	print("[quit] scene now: ", get_tree().current_scene.scene_file_path, "  playing ", Server.playing)
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
