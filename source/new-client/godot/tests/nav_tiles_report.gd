extends SceneTree
## Debug: polygons per cached navigation tile of a zone (a 7 x 7 grid).  -s res://tests/nav_tiles_report.gd -- <dir> <zone> <tag>
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var lines := ""
	for tz in 7:
		var row := ""
		for tx in 7:
			var nm := ResourceLoader.load("%s/zone%03d_%s_%d_%d.res" % [a[0], int(a[1]), a[2], tx, tz]) as NavigationMesh
			row += "%7d" % (nm.get_polygon_count() if nm else -1)
		lines += row + "\n"
	print(lines)
	quit()
