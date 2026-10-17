extends Node
## Debug: how far spawns sat off the floor before settling (NpcManager.settle_report).
##   --headless --skip-login --zone=202 --figure=cel_m --ui-test --probe=float_audit
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var rep: Array = v.npcs.settle_report
	var up := rep.filter(func(r): return float(r[1]) > 0.15)
	var down := rep.filter(func(r): return float(r[1]) < -0.15)
	print("[float] zone %s: %d spawns, %d settled, %d were floating > 0.15 m, %d sunk > 0.15 m" % [v.zone.info.id, v.npcs.states.size(), rep.size(), up.size(), down.size()])
	up.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for r in up.slice(0, 12):
		print("[float]   up %.2f m  %s" % [float(r[1]), r[0]])
	down.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	for r in down.slice(0, 6):
		print("[float]   sunk %.2f m  %s" % [-float(r[1]), r[0]])
	get_tree().quit()
