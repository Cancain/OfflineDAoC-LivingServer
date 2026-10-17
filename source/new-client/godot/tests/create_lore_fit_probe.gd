extends SceneTree
## Debug (owner 2026-10-15: the create screen's lore must fit its box): every race + base text and every class_lore
## text in the create screen's description box (210 x 504, Minion Pro 14, ALL CAPS - pregame.gd _build_create), its
## height and whether it overflows. Headless, quits by itself.
##   Godot --headless --path godot -s res://tests/create_lore_fit_probe.gd


func _initialize() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/pregame/pregame.json"))
	var font := FontFile.new()
	font.load_dynamic_font("res://content/ui/fonts/minionpro-regular.ttf")
	var texts := {}
	for k in meta.classes:
		texts[k] = String(meta.classes[k].get("text", ""))
	for k in meta.get("class_lore", {}):
		texts["lore:" + k] = String(meta.class_lore[k])
	var d := RichTextLabel.new()
	d.bbcode_enabled = false
	d.scroll_active = false
	d.add_theme_font_override("normal_font", font)
	d.add_theme_font_size_override("normal_font_size", 14)
	d.size = Vector2(210, 504)
	root.add_child(d)
	await process_frame
	var worst := ["", 0]
	var over := []
	for k in texts:
		d.text = String(texts[k]).strip_edges().to_upper()
		await process_frame
		await process_frame
		var h := d.get_content_height()
		for fs in [14, 13, 12, 11]:                         # as pregame.gd _fit_desc
			d.add_theme_font_size_override("normal_font_size", fs)
			await process_frame
			await process_frame
			h = d.get_content_height()
			if h <= 504:
				if fs < 14:
					print("[fit]   %s fits at %d (%d px)" % [k, fs, h])
				break
		d.add_theme_font_size_override("normal_font_size", 14)
		if h > worst[1]:
			worst = [k, h]
		if h > 504:
			over.append("%s %d" % [k, h])
	print("[fit] %d texts, tallest %s %d px of 504; overflowing: %s" % [texts.size(), worst[0], worst[1], over])
	quit()
