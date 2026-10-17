extends Node
## Debug (windowed): the equipment window's figure for the tallest / smallest races, side by side (owner: the male
## troll was cut off).   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --no-npcs --probe=doll_fit_shots --out=<folder>
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(4.0).timeout
	var out := String(v.args.get("out", "user://"))
	var imgs := []
	for prefix in ["tro_m", "tro_f", "lur_m", "fir_m", "cel_f", "nor_m"]:
		PlayerData.character["prefix"] = prefix
		var d := InventorySheet.DollView.new()
		d.size = InventorySheet.DOLL.size
		v.ui.add_child(d)
		d.build()
		await get_tree().create_timer(0.8).timeout
		imgs.append(d._vp.get_texture().get_image())
		d.queue_free()
	var w: int = (imgs[0] as Image).get_width()
	var h: int = (imgs[0] as Image).get_height()
	var sheet := Image.create(w * imgs.size(), h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in imgs.size():
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(out + "/dolls.png")
	get_tree().quit()
