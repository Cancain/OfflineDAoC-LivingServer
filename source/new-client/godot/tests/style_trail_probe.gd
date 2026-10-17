extends Node
## Debug (owner 2026-10-10: the colour flash of melee styles): the player in attack mode with a sword performs a style
## (its own clip + StyleTrail with the style's styles.csv trail); pictures from the side through the swing.
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=style_trail_probe --out=<dir> [--style=58]
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = v.combat
	PlayerData.inventory[10] = {"id": "practice_sword"}
	PlayerData.active_weapon = "standard"
	v.player.refresh_gear()
	combat.set_attack_mode(true)
	await get_tree().create_timer(1.0).timeout
	var style := ClassDb.style_by_game_id(int(v.args.get("style", "58")), 1)
	var trail = StyleTrail.trail_of(style)
	print("[trail] style %s, trail %s, held weapons %d" % [style.get("name"), trail, StyleTrail.held(v.player._model).size()])
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var p: Vector3 = v.player.global_position
	var side: Vector3 = v.player._model.global_transform.basis.x
	cam.global_position = p + side * 3.0 + Vector3(0, 1.3, 0)
	cam.look_at(p + Vector3(0, 1.0, 0))
	var clip: String = v.player.play_style(int(style.get("animation", 0)))
	StyleTrail.play(v.player.get_parent(), StyleTrail.held(v.player._model), trail)
	print("[trail] clip ", clip, " ", v.player.clip_seconds(clip), " s")
	var out := String(v.args.get("out", "user://"))
	for i in 6:
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/trail_%d.png" % [out, i])
	get_tree().quit()
