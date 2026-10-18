extends Node
## Debug (player report 2026-10-17: Iarnvidiur's Lair - pulling Dyranapur / Lydsyg with a full companion party slows the
## game down, then it crashes; their Black Plague is a 450-radius disease recast on 45% of their hits): Claude's GM test
## character made level 50, jumped beside --boss (Dyranapur), a full /spawn companion group, /pull - then every 2 s the
## frame rate, memory, video memory, nodes, live spell effects and spell packets. Runs once (--secs, 150 s cap).
var v: Node
var _fx_packets := 0
var _fx_by := {}
var _all_chat := false


func _ready() -> void:
	var secs := float(get_tree().current_scene.args.get("secs", "120"))
	get_tree().create_timer(minf(secs + 40.0, 170.0)).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k):
		var s := String(t).to_lower()
		if _all_chat or "level" in s or "spawn" in s or "disease" in s or "plague" in s or "companion" in s or "die" in s or "killed" in s:
			print("[chat] ", t))
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind == "spell_effect":
			_fx_packets += 1
			var k := str(d.get("effect", d.get("spell", "?")))
			_fx_by[k] = int(_fx_by.get(k, 0)) + 1)
	await _wait(8.0)
	Server.client.call("Target", Server.me_oid, 0x6000)
	await _wait(1.0)
	Server.command("/player level 50")
	await _wait(3.0)
	Server.command("/jump to 31981 24137 15602 161")
	await _wait(10.0)
	for c in String(v.args.get("party", "Hero,Druid,Champion,Mentalist,Blademaster,Warden,Bard")).split(","):
		Server.command("/spawn " + c)
		await _wait(1.5)
	await _wait(6.0)
	var sw: ServerWorld = v.npcs
	var boss_name := String(v.args.get("boss", "Dyranapur")).to_lower()
	var boss: Npc = null
	for st in sw.by_oid.values():
		if (st as NpcState).view and String((st as NpcState).spawn.get("name", "")).to_lower() == boss_name:
			boss = (st as NpcState).view
	print("[plague] boss view ", boss != null)
	_all_chat = true
	if boss:
		var oid := 0
		for k in sw.by_oid:
			if (sw.by_oid[k] as NpcState).view == boss:
				oid = int(k)
		var at := Server.to_region(sw._current_zone(), boss.global_position)
		Server.command("/jump to %d %d %d 161" % [int(at.x) + 120, int(at.y), int(at.z)])   # beside it, as it is now
		await _wait(4.0)
		sw.select(boss)
		Server.client.call("Target", oid, 0x8000 | 0x6000)
		await _wait(1.0)
		Server.command("/pull")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await _wait(2.0)
		print("[plague] t=%3d fps %5.1f  mem %6.0f MB  vram %6.0f MB  nodes %6d  orphans %5d  live fx %3d  fx packets %5d  effects %3d" % [
				(Time.get_ticks_msec() - t0) / 1000, Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				SpellFx._live.size(), _fx_packets, Server.effects.size()])
	var top := _fx_by.keys()
	top.sort_custom(func(a, b): return _fx_by[a] > _fx_by[b])
	print("[plague] effect packets by effect: ", top.slice(0, 8).map(func(k): return "%s x%d" % [k, _fx_by[k]]))
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
