extends Node
## Debug (owner 2026-10-14: after setting the FPS target to OFF and back to 60 the target never worked again until a
## restart): on a test server run, a jump to Tir na Nog's bind area (a crowd), then perf_switch_run.gd measures.


func _ready() -> void:
	await get_tree().create_timer(8.0).timeout
	var helper := Node.new()
	helper.set_script(load("res://tests/perf_switch_run.gd"))
	get_tree().root.add_child(helper)
	Server.command("/jump to 29825 33165 7920 201")
