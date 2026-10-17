extends Node
## Debug: a spell's landing effect played on the player, screenshotted over its life (user://fx_<ce>_<n>.png) and its
## particle systems listed. --ce=<client effect> (default 3409, Fungal Decrepitude)
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=fx_shot
func _ready() -> void:
	var v := get_tree().current_scene
	var ce := 3409
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ce="):
			ce = int(a.get_slice("=", 1))
	await get_tree().create_timer(5.0).timeout
	var e := SpellFx.effect(ce)
	print("[fx] effect ", e)
	var fx: Node3D = SpellFx.play(int(e.target), v.player, 1.8)
	print("[fx] node ", fx)
	await get_tree().process_frame
	if fx:
		for p in fx.find_children("*", "GPUParticles3D", true, false):
			var gp := p as GPUParticles3D
			print("[fx] particles ", gp.name, " emitting ", gp.emitting, " amount ", gp.amount, " lifetime ", gp.lifetime,
					" vis_end ", gp.visibility_range_end, " pm ", gp.process_material, " draw ", gp.draw_pass_1)
		print("[fx] global ", fx.global_transform, " visible ", fx.is_visible_in_tree())
	for i in 4:
		await get_tree().create_timer(0.7).timeout
		get_viewport().get_texture().get_image().save_png("user://fx_%d_%d.png" % [ce, i])
	get_tree().quit()
