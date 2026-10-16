extends Node
## Debug, test server (owner 2026-10-15: sjoalf waverunners standing in water, companions and their pets never swim):
## jumps to the waverunners (region 151) and logs every living near you - the server's height, the water and ground
## our client finds there, the server's underwater flag, swimming, the clip shown. Runs once; hard stop 120 s.
var v: Node
var t0 := 0


func _ready() -> void:
	if get_tree().root.has_meta("swim_npc_ran"):
		return
	get_tree().root.set_meta("swim_npc_ran", true)
	get_tree().create_timer(120.0).timeout.connect(func(): Server.quit_world(true))
	t0 = Time.get_ticks_msec()
	await _wait(8.0)
	reparent.call_deferred(get_tree().root)                # (a jump to another region loads a new scene)
	await _wait(1.0)
	Server.command("/jump to 435900 339400 6442 151")
	await _wait(30.0)                                       # the region's zones load
	v = get_tree().current_scene
	_report()
	await _wait(10.0)
	v = get_tree().current_scene
	_report()
	Server.quit_world(true)


func _report() -> void:
	var sw: ServerWorld = v.npcs as ServerWorld
	if sw == null:
		print("[sw] no server world")
		return
	var me: Vector3 = v.player.global_position
	print("[sw] you at %s, water here %.2f, ground %.2f" % [me.snapped(Vector3.ONE * 0.1), sw._water_at(me), sw._grid_at(me)])
	var n := 0
	for oid in sw.by_oid:
		var st: NpcState = sw.by_oid[oid]
		if st.pos.distance_to(me) > 70.0 or n > 14:
			continue
		n += 1
		var mv: Dictionary = sw._mover.get(st, {})
		var view: Npc = st.view
		print("[sw] %-28s y %.2f srv %.2f water %.2f grid %.2f flag %s swimming %s clip '%s' has swim %s" % [st.spawn.name,
				st.pos.y, float(mv.get("sy", st.pos.y)), sw._water_at(st.pos), sw._grid_at(st.pos), mv.get("water", "-"),
				st.swimming, view.anim.current_animation if view and view.anim else "-",
				view.anim.has_animation("swim") if view and view.anim else false])


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
