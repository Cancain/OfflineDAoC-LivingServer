extends Node
## Debug (owner 2026-10-10: the concentration system + window): a level 30 Druid casts its concentration buffs on
## itself until the pool or the limit says no; the window; shift-right-click cancel; death ends them.
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=conc_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	PlayerData.message.connect(func(t, k):
		if k in ["spells", "system"]:
			print("[chat] ", t))
	var druid := 47
	PlayerData.level = 30
	PlayerData.promote(druid)
	PlayerData.specs = {}
	for e in ClassDb.specs_at(druid, 30):
		PlayerData.specs[String(e.get("key", e.get("spec", "")))] = 30
	PlayerData.recalc_max()
	var cs: Casting = v.combat.casting
	var conc := []
	for line in ClassDb.spell_lines(druid, 30, PlayerData.specs):
		for sid in line.spells:
			var sp := ClassDb.spell(int(sid))
			if int(sp.get("concentration", 0)) > 0 and String(sp.get("target", "")).to_lower() in ["self", "realm", "group"]:
				conc.append(sp)
	print("[conc] max ", cs.max_conc(), " conc spells known ", conc.size(), ": ", conc.map(func(s): return "%s(%d)" % [s.name, int(s.concentration)]))
	v.ui.windows["conc"].show_window()
	for sp in conc:
		PlayerData.set_power(PlayerData.max_power)
		cs.interrupt_until = 0.0
		PlayerData.use_skill.emit({"kind": "spell", "id": int(sp.spellid)})
		await get_tree().create_timer(float(sp.get("casttime", 3.0)) + 0.6).timeout
		print("[conc] after ", sp.name, ": used ", cs.conc_used(), " / ", cs.max_conc(), "  effects ", cs.conc_effects().size())
	await get_tree().create_timer(0.5).timeout
	if v.args.has("out"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(v.args.out) + "/conc_window.png")
	cs.cancel_conc(0)
	await get_tree().create_timer(0.3).timeout
	print("[conc] after cancel: used ", cs.conc_used(), " effects ", cs.conc_effects().size())
	v.combat._player_died()
	await get_tree().create_timer(0.3).timeout
	print("[conc] after death: used ", cs.conc_used(), " effects on you ", cs.player_effects().size())
	get_tree().quit()
