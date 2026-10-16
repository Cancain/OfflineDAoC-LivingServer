extends SceneTree
## Check (bot plan phase 2): the realm split's bot counts always add up to the total (largest remainder).
func _initialize() -> void:
	var third := 100.0 / 3.0
	for c in [[1500, [third, third, third]], [3000, [third, third, third]], [1000, [third, third, third]],
			[1, [third, third, third]], [1500, [50.0, 25.0, 25.0]], [2000, [60.0, 30.0, 10.0]], [0, [third, third, third]]]:
		var r := RealmSettings.realm_counts(c[0], c[1])
		print("[counts] %d at %s -> %s (sum %d)" % [c[0], str(c[1]).left(40), r, r[0] + r[1] + r[2]])
	quit()
