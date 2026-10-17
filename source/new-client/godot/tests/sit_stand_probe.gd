extends Node
## Debug (owner 2026-10-10: after /sit, W slid the character along without the run for seconds): sit, then walk off
## (autorun) and log the clip; then sit and /stand in place and log the clip as it rises.
##   --screen 1 --skip-login --figure=bri_m --probe=sit_stand_probe
func _ready() -> void:
	var v := get_tree().current_scene
	var p: Player = v.player
	await get_tree().create_timer(4.0).timeout
	for leg in ["walk off", "stand in place"]:
		v.combat.sit(true, true)
		await get_tree().create_timer(2.0).timeout
		print("[sit] %s: sitting clip=%s" % [leg, p._anim.current_animation])
		if leg == "walk off":
			p.autorun = true
		else:
			v.combat.sit(false, true)
		for i in 8:
			await get_tree().create_timer(0.25).timeout
			print("[sit] %s t=%.2f clip=%s pos=%.2f speed=%.2f sitting=%s vel=%.1f" % [leg, (i + 1) * 0.25,
					p._anim.current_animation, p._anim.current_animation_position, p._anim.get_playing_speed(),
					p.sitting, p.velocity.length()])
		p.autorun = false
		await get_tree().create_timer(1.0).timeout
	get_tree().quit()
