class_name BotViewTicker
extends Node


## A clicked gamebot / companion on your target bar: its health now (four times a second) - it showed full forever
## (owner 2026-10-11: a bot dying to a monster stayed at 100%).
func _refresh_target() -> void:
	if not PlayerData.target.has("bot"):
		return
	var gb: Node = get_parent().get("bots")
	if gb == null:
		return
	var h := float(gb.call("Health", int(PlayerData.target.bot)))
	if h < 0.0:
		return                                             # (not in this zone any more)
	if absf(h - float(PlayerData.target.get("health", 1.0))) > 0.001:
		PlayerData.target["health"] = h
		PlayerData.target_changed.emit()
## Steps every gamebot / companion figure (BotView.tick) from one place - per-figure _process calls cost a crowd ~12 ms
## a frame (crowd_probe). Like NpcManager's view loop: within 20 m of the camera every frame, within 45 m every 2nd,
## farther every 4th, with the time gathered (AnimLod still decides how often a skeleton is posed).
var _frame := 0


var _target_left := 0.0


func _process(delta: float) -> void:
	_target_left -= delta
	if _target_left <= 0.0:
		_target_left = 0.25
		_refresh_target()
	var vs: Array = BotView.views
	if vs.is_empty():
		return
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	AnimLod.snapshot(cam)                                  # (threaded posing: the views step after this)
	var scene := get_tree().current_scene
	var p = scene.get("player") if scene else null
	var pp: Vector3 = (p as Node3D).global_position if p is Node3D else (cam.global_position if cam else Vector3.ZERO)
	if AnimLod.threaded:                                    # the figures pose themselves; here only their plates
		for i in vs.size():
			var b: BotView = vs[i]
			if b.lod_dist() < 45.0 or b.targeted or (_frame + i) % 4 == 0:
				b.plate(cam, pp)
		return
	for i in vs.size():
		var b: BotView = vs[i]
		b.pending += delta
		var d := b.lod_dist()
		var stride := 1 if AnimLod.FULL or Perf.brute or d < AnimLod.NEAR_FULL_M else (2 if d < 45.0 else 4)
		if (_frame + i) % stride == 0:
			b.tick(b.pending, cam, pp)
			b.pending = 0.0
