extends Node
## Debug (owner 2026-10-14: /hood and /helm do nothing; a skald's songs show the minstrel's musical notes; a skald's
## speed song lost after a zone change). On a test server run: a cloak and a cap put on (/item create), /hood and
## /helm (the server's flags, the figure's), the skald's Song of Travel and the minstrel's Song of Minor Renewal fired on
## you (the caster effects shown), then /sprint and a jump to Domnann (another region): your speed in the new world
## (speed_after_region.gd). Screenshots user://hoodskald_<n>.png.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	if v.args.has("speed_only"):
		await _speed()
		return
	for pair in [["cloak", 26, 57], ["Tattered_Woolen_Cap", 21, 826]]:
		if not PlayerData.inventory.has(pair[1]):
			Server.command("/item create %s" % pair[0])
			await _wait(1.5)
			var from := _slot_of(int(pair[2]))
			if from >= 0:
				PlayerData.move(from, int(pair[1]))
				await _wait(1.5)
	_report("worn")
	await _shot(0)
	for cmd in ["/hood", "/helm", "/hood", "/helm"]:
		Server.command(cmd)
		await _wait(2.0)
		_report(cmd)
		if cmd == "/hood" and bool(Server.gear.get("hood", false)) or cmd == "/helm" and bool(Server.gear.get("helm_hidden", false)):
			await _shot(1 if cmd == "/hood" else 2)
	# the songs' caster effects (spells.csv Effect2 108 = the minstrel's musical notes)
	for ce in [3609, 1111]:
		var before := SpellFx._live.keys()
		SpellFx.fire(ce, [], v.player, null)
		await _wait(0.3)
		var made := []
		for k in SpellFx._live:
			if not before.has(k) and is_instance_valid(SpellFx._live[k]):
				made.append(String((SpellFx._live[k] as Node).get_meta("fx_path", "?")).get_base_dir().get_file())
		print("[hs] effect %d (%s): caster effects %s" % [ce, SpellFx.effect(ce).get("name", "?"), made])
	await _speed()


func _speed() -> void:
	Server.use("srv:spell:0:1")                             # (a cast ends the login stealth: no sprint while hidden)
	await _wait(5.0)
	# speed across a region change
	Server.command("/cast spell 3609")                     # the skald's Song of Travel on yourself (GM cast)
	await _wait(3.0)
	print("[hs] Song of Travel: server speed %d%%, your speed x%.2f  effects %s" % [Server.max_speed_pct,
			v.player.encumbrance, Server.effects.values().map(func(e): return e.get("name", "?"))])
	var helper := Node.new()
	helper.set_script(load("res://tests/speed_after_region.gd"))
	get_tree().root.add_child(helper)
	# another region than where you are: Domnann (Shrouded Isles, region 181) or Connacht (region 200)
	var in_si := int(Server.entry.get("region", 0)) == 181
	Server.command("/jump to 319488 450560 5728 200" if in_si else "/jump to 425984 425984 4450 181")


func _report(what: String) -> void:
	var fig = v.player.get("_model")
	print("[hs] %s: server gear %s  figure hood %s helm hidden %s  helm %s" % [what, Server.gear,
			fig.hood_up if fig is Fig3Figure else "-", fig.helm_hidden if fig is Fig3Figure else "-",
			PlayerData.item_at(21).get("name", "-")])


func _slot_of(model: int) -> int:
	for s in PlayerData.inventory:
		if int(s) >= PlayerData.BACKPACK and int(PlayerData.item_at(int(s)).get("model", 0)) == model:
			return int(s)
	return -1


func _shot(n: int) -> void:
	v.player.face(v.player.facing() + PI)
	await _wait(0.8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://hoodskald_%d.png" % n)
	v.player.face(v.player.facing() + PI)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
