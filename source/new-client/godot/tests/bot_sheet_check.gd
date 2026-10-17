extends SceneTree
## Bot plan phase 4 (owner 2026-10-11: bots and players share rules): a gamebot's own CharacterState - made the way
## bots are made (CharacterFactory), its starting gear, stats, hit points, and levels from kill experience.
##   --headless --path godot -s res://tests/bot_sheet_check.gd


func _initialize() -> void:
	await process_frame
	for realm in ["alb", "mid", "hib"]:
		var c := CharacterFactory.random_character(realm, 1234)
		var s := CharacterState.new()
		s.is_bot = true
		var lines := []
		s.message.connect(func(t, _k): lines.append(t))
		s.load_sheet(c)
		s.recalc_max()
		s.hp = s.max_hp
		print("[sheet] %s %s %s L%d class %d stats %s hp %d/%d power %d weapon %s gear %s" % [realm, c.name, c.class_name,
				s.level, s.class_id(), s.effective_stats(), s.hp, s.max_hp, s.max_power, s.active_weapon,
				s.inventory.keys()])
		for i in 12:
			s.gain_xp(CombatRules.kill_xp(s.level, s.level, false))
		print("[sheet]   after kills: L%d xp %d hp %d specs %s" % [s.level, s.xp, s.max_hp, s.specs])
		print("[sheet]   said: %s" % " | ".join(lines.slice(-3)))
		s.store_sheet()
		print("[sheet]   stored level %s, inventory %d entries" % [c.level, (c.inventory as Dictionary).size()])
		s.free()
	quit()
