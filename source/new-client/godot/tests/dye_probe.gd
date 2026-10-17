extends Node
## Debug (owner 2026-10-14: dyes and enamel on gear show their colour): on a test server run, Claude's GM test magician
## gets a blue cloth dye and a blue weapon luster (/item create), drops the dye on the worn robe and the luster on the
## staff (as the inventory's drag and drop does), and the colours the server sends back and the figure draws -
## screenshots user://dye_<n>.png; then the window closes itself.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	await _wait(8.0)
	print("[dye] worn: ", _worn())
	await _shot(0)
	for id in ["blue_cloth_dye", "blue_weapon_luster"]:
		Server.command("/item create %s" % id)
		await _wait(1.5)
	var dye := _slot_of(229)
	var luster := _slot_of(538)
	print("[dye] in the backpack: cloth dye slot %d, weapon luster slot %d" % [dye, luster])
	# the worn cloth: the torso (25) else any armour piece; the weapon: the two-hander (12) else the right hand (10)
	var robe := 25 if PlayerData.inventory.has(25) else -1
	for s in [25, 27, 28, 22, 23, 26]:
		if robe < 0 and PlayerData.inventory.has(s):
			robe = s
	var weapon := 12 if PlayerData.inventory.has(12) else 10
	# the server dyes in the backpack only (a dye can't go in a worn slot): off, dyed, back on
	for pair in [[dye, robe], [luster, weapon]]:
		if pair[0] < 0 or pair[1] < 0 or not PlayerData.inventory.has(pair[1]):
			continue
		var free := -1
		for s in range(PlayerData.BACKPACK, PlayerData.BACKPACK + 40):
			if not PlayerData.inventory.has(s):
				free = s
				break
		PlayerData.move(pair[1], free)
		await _wait(1.5)
		PlayerData.move(pair[0], free)
		await _wait(1.5)
		print("[dye]   in the backpack after the dye: ", PlayerData.item_at(free).get("name"), " colour ", PlayerData.item_at(free).get("color"))
		PlayerData.move(free, pair[1])
		await _wait(1.5)
	var zid := int(v.region.current.info.id) if v.region and v.region.current else int(v.zone.info.id)
	Server.switch_weapon("twohand", v.player, zid)          # (taken off, the staff left the active set)
	await _wait(2.0)
	print("[dye] after: ", _worn(), "  active ", PlayerData.active_weapon)
	var fig = v.player.get("_model")
	print("[dye] figure armour tints: ", fig.armor_tints if fig is Fig3Figure else "-")
	var tints := []
	for n in v.player.get("_gear") if v.player.get("_gear") is Array else []:
		if is_instance_valid(n):
			for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).get_active_material(0)
				if m is ShaderMaterial:
					tints.append((m as ShaderMaterial).get_shader_parameter("tint"))
	print("[dye] weapon material tints: ", tints)
	await _shot(1)
	get_tree().quit()


func _worn() -> Dictionary:
	var out := {}
	for s in [10, 11, 12, 13, 21, 22, 23, 25, 26, 27, 28]:
		if PlayerData.inventory.has(s):
			var it := PlayerData.item_at(s)
			out[s] = "%s (model %s, colour %s)" % [it.get("name", "?"), it.get("model", "?"), it.get("color", 0)]
	return out


func _slot_of(model: int) -> int:
	for s in PlayerData.inventory:
		if int(s) >= PlayerData.BACKPACK and int(PlayerData.item_at(int(s)).get("model", 0)) == model:
			return int(s)
	return -1


func _shot(n: int) -> void:
	v.player.face(v.player.facing() + PI)              # (the camera behind: turn to show the front)
	await _wait(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://dye_%d.png" % n)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
