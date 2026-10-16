extends Node
## The game's side of the bots it draws (autoload WorldLink): your companions (GameBots, C#). The world's gamebots,
## monsters and NPCs come from the Offline DAoC server the launcher runs (Offline DAoC Rebuilt, owner 2026-10-11) - the
## MMOEngine world host is gone.

var bots: Node = null                         # GameBots (C#): your companions


func _ready() -> void:
	set_process(false)
	for a in OS.get_cmdline_user_args():                     # the launcher's server game: the server runs every bot
		if a.begins_with("--server="):
			return
	if OS.get_executable_path().to_lower().contains("mono"):
		var gb = load("res://game/world_host/GameBots.cs")
		if gb:
			bots = gb.new()
			bots.name = "GameBots"
			add_child(bots)
			var ticker := BotViewTicker.new()                 # steps every bot figure (BotView.tick)
			ticker.name = "BotViewTicker"
			add_child(ticker)


# --- the zone you're in (ZoneViewer) and the bots in it (GameBots) -------------------------------------------------

func zone_entered(zone: Node3D, zone_id: int) -> void:
	if bots:
		bots.call("ZoneEntered", zone, zone_id)


## Seamless zones: you walked over a border into another zone of the region (no loading screen) - the old zone's bots
## go back to the host, the new zone's come; your companions walk on with you.
func zone_switched(zone: Node3D, zone_id: int) -> void:
	if bots:
		bots.call("SwitchZone", zone, zone_id)


func zone_left() -> void:
	if bots:
		bots.call("ZoneLeft")


## The bot under a click (its BotView), or null.
func pick_bot(cam: Camera3D, screen: Vector2) -> Node3D:
	return bots.call("Pick", cam, screen) if bots else null


## Target a bot: its nameplate goes white, the target window shows it ("You target [Name].", the period chat line).
func target_bot(view: Node3D) -> void:
	if bots == null or view == null:
		return
	bots.call("SetTarget", int(view.get("bot_id")))
	var rec: Dictionary = view.get("record")
	var nm: String = view.call("display_name")
	PlayerData.message.emit("You target [%s]." % nm, "system")
	# owner 2026-10-11: "You examine X. They are a level N <class> in your realm." (an enemy: what you can see of them
	# - race and rank - and their realm; a companion: yours)
	var lv := int(rec.get("level", 1))
	var cls := String(rec.get("class_name", "adventurer"))
	if bool(view.get("companion")):
		PlayerData.message.emit("You examine %s. They are a level %d %s, your companion." % [nm, lv, cls], "system")
	elif String(rec.get("realm", "")) == PlayerData.realm_key():
		PlayerData.message.emit("You examine %s. They are a level %d %s in your realm." % [nm, lv, cls], "system")
	else:
		var realm_name: String = {"alb": "Albion", "mid": "Midgard", "hib": "Hibernia"}.get(String(rec.get("realm", "")), "another realm")
		PlayerData.message.emit("You examine the %s. They are a level %d %s of %s." % [nm, lv, cls, realm_name], "system")
	# its con to you, the NPCs' colours (owner 2026-10-11: the bar showed every bot white)
	var npcs = get_tree().current_scene.get("npcs") if get_tree().current_scene else null
	var con_color := Color.WHITE
	if npcs is NpcManager:
		con_color = Npc.CON_COLORS.get((npcs as NpcManager).con_level(PlayerData.level, int(rec.get("level", 1))), Color.WHITE)
	PlayerData.set_target({"name": nm, "level": int(rec.get("level", 1)), "con_color": con_color, "health": 1.0,
			"guild": String(rec.get("guild", "")), "bot": int(view.get("bot_id"))})


func clear_bot_target() -> void:
	if bots and int(bots.get("TargetId")) >= 0:
		bots.call("SetTarget", -1)


## Your realm's bots in your zone, for the map's green dots (Options > BOTS > REALM BOTS ON MAP; enemy bots never).
func bot_dots() -> PackedVector3Array:
	if Server.active:                                      # the server's bots (its map markers)
		return Server.bot_dots() if BotView.option("map_dots") else PackedVector3Array()
	if bots == null or not BotView.option("map_dots"):
		return PackedVector3Array()
	return PackedVector3Array(bots.call("FriendlyDots", PlayerData.realm_key()))


## Your companions in your zone, for the map (their own colour - owner 2026-10-11).
func companion_dots() -> PackedVector3Array:
	return PackedVector3Array(bots.call("CompanionDots")) if bots else PackedVector3Array()


## The inspect key (diagnostics): the targeted bot's state and its last decisions, into the chat.
func inspect_target() -> void:
	if bots == null or int(bots.get("TargetId")) < 0:
		PlayerData.message.emit("Target a bot first to inspect it.", "system")
		return
	for line in String(bots.call("Inspect", int(bots.get("TargetId")))).split("\n"):
		PlayerData.message.emit("[BOT] " + line, "system")
