extends SceneTree
## Lists every class's known abilities at 50 (all specs 50), skipping weaponry / armour / passive defence ones.
func _initialize() -> void:
	await process_frame
	ClassDb.cls(1)
	var skip := ["Weaponry", "AlbArmor", "HibArmor", "MidArmor", "Shield", "Evade", "Parry", "Advanced Evade", "Enhanced Evade", "Sprint"]
	var all := {}
	for k in ClassDb._classes:
		var c: Dictionary = ClassDb._classes[k]
		if bool(c.get("is_base", false)):
			continue
		var specs := {}
		for e in ClassDb.trainable_specs(int(c.id), 50):
			specs[String(e.spec)] = 50
		var names := []
		for a in ClassDb.abilities_known(int(c.id), 50, specs):
			var n := String(a.key)
			var keep := true
			for s in skip:
				if n.begins_with(s):
					keep = false
			if keep:
				names.append(n)
				all[n] = int(all.get(n, 0)) + 1
		print(c.name, ": ", names)
	print("ALL ", all)
	quit()
