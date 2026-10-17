extends Node
func _ready() -> void:
	var f := Fig3Figure.new()
	add_child(f)
	f.load_figure("nor_f")
	var t0 := Time.get_ticks_usec()
	var all := f.find_children("*", "GeometryInstance3D", true, false)
	var t1 := Time.get_ticks_usec()
	for g in all:
		(g as GeometryInstance3D).layers = 2
	var t2 := Time.get_ticks_usec()
	var nodes := f.find_children("*", "", true, false).size()
	var vis := 0
	for g in all:
		if (g as Node3D).is_visible_in_tree():
			vis += 1
	print("[bench] nodes ", nodes, " geoms ", all.size(), " visible ", vis, " find ", (t1 - t0) / 1000.0, " ms set ", (t2 - t1) / 1000.0, " ms")
	var t3 := Time.get_ticks_usec()
	for g in all:
		(g as GeometryInstance3D).layers = 2
	print("[bench] set again ", (Time.get_ticks_usec() - t3) / 1000.0, " ms")
	get_tree().quit()
