extends Node
## Debug (owner 2026-10-14: /loc in chat; buff / debuff hover says nothing; the trainer's Pts box empty and Realm Skills
## empty; spell tooltips mismatched - Fungal Pin showed a buff, buffs had none, no heal / damage details on hover): on
## the running server with Claude's GM test Animist - /loc typed, Force of the Deep cast on yourself and its icon's
## hover box, the hover / right-click text of the first spells of every list, then the Animist trainer's window
## (screenshots user://tooltip_<n>.png).
var v: Node
var _info := []


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	var sw: ServerWorld = v.npcs
	Server.command("/jump to 297302 643167 4850 200")     # beside Ailinh, Forester trainer
	await _wait(14.0)
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	# --- /loc
	v.ui.chat.run_line("/loc")
	await _wait(1.0)
	# --- a buff on yourself and its icon's hover text
	sw.clear_target()
	Server.command("/cast spell 3253")
	await _wait(2.0)
	var effs: Array = Server.effects_list()
	print("[tip] effects: ", effs.map(func(e): return [e.name, e.fx]))
	for e in effs:
		Server.prefetch_effect(int(e.fx), String(e.name))
	await _wait(1.5)
	for e in effs:
		print("[tip] effect hover ", e.name, ": ", Server.effect_lines(int(e.fx)))
	var box: Control = null
	for c in v.ui._effects_bar.get_children():
		if int(c.get("fx")) == 3253:
			box = c
	if box:
		var at := box.get_global_rect().get_center()
		get_viewport().warp_mouse(at)
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.global_position = at
		get_viewport().push_input(mm)
		await _wait(0.2)
		var hov := get_viewport().gui_get_hovered_control()
		print("[tip] under the pointer at the first effect icon: ", hov, " (", hov.get_class() if hov else "", ")  is the box: ", hov == box)
		var tip = box.call("_make_custom_tooltip", "")
		print("[tip] its hover box: ", _box_text(tip))
		await _wait(1.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://tooltip_1.png")
	# --- spells: hover text for the first spells of every list, and the hybrid / ability rows
	var asked := []
	for li in Server.spell_lines.size():
		var line: Dictionary = Server.spell_lines[li]
		for sp in (line.spells as Array).slice(0, 3):
			var e := {"kind": String(sp.get("kind", "spell")), "id": "srv:spell:%d:%d" % [li, int(sp.level)], "name": String(sp.name)}
			asked.append(e)
	var first := 0
	for i in Server.skills.size():
		if int(Server.skills[i].page) != 0:
			first = i
			break
	for i in range(first, mini(Server.skills.size(), first + 6)):
		var sk: Dictionary = Server.skills[i]
		asked.append({"kind": {2: "style", 3: "spell", 4: "spell"}.get(int(sk.page), "ability"), "id": "srv:skill:%d" % (i - first),
				"name": String(sk.name)})
	for e in asked:
		Server.prefetch_skill(e)
	await _wait(3.0)
	for e in asked:
		var d := Server.skill_lines(e)
		print("[tip] hover ", e.name, " ", Server.skill_detail(e), " -> ", String(d.get("caption", "(none)")), " | ",
				" / ".join((d.get("lines", []) as Array).slice(0, 6)))
	# --- the trainer
	for _i in 40:                                          # (the town's views come in over a few seconds)
		var ready := false
		for st in sw.by_oid.values():
			if (st as NpcState).view and String((st as NpcState).spawn.name).to_lower().contains("ailinh"):
				ready = true
		if ready:
			break
		await _wait(0.5)
	var tr: Npc = null
	var near := []
	for st in sw.by_oid.values():
		var s2: NpcState = st
		if s2.view and String(s2.spawn.name).to_lower().contains("ailinh"):
			tr = s2.view
		near.append([s2.pos.distance_to(v.player.global_position), String(s2.spawn.name), s2.view != null])
	near.sort()
	print("[tip] nearest: ", near.slice(0, 6))
	print("[tip] trainer: ", tr != null)
	if tr:
		sw.select(tr)
		await _wait(0.5)
		sw.interact(tr)
		await _wait(3.0)
		print("[tip] realm skills: ", Server.realm_abilities.size(), " points ", Server.ra_points, "  window open: ", v.ui.trainer.visible,
				"  spec points label: ", v.ui.trainer._points.text)
		for ra in Server.realm_abilities.slice(0, 5):
			print("[tip]   ", ra)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://tooltip_2.png")
	get_tree().quit()


func _box_text(c) -> String:
	if c == null:
		return "(none - the plain name)"
	var out := []
	for l in (c as Node).get_children():
		if l is Label:
			out.append((l as Label).text)
	(c as Node).queue_free()
	return " / ".join(out)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
