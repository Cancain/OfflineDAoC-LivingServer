extends Node
## Debug: list the particle systems the zone built (name, amount, lifetime, position in DAoC units).

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var zone: ZoneLoader = get_tree().current_scene.zone
	var n := 0
	for c in zone.get_children():
		if c is GPUParticles3D:
			n += 1
			var p := c as GPUParticles3D
			var pm := p.process_material as ParticleProcessMaterial
			print("%-28s amount %3d life %.2f vel %.2f-%.2f spread %.0f grav %s at %d,%d,%d" % [p.name, p.amount, p.lifetime,
				pm.initial_velocity_min, pm.initial_velocity_max, pm.spread, str(pm.gravity.snapped(Vector3.ONE * 0.01)),
				p.global_position.x / 0.025, p.global_position.z / 0.025, p.global_position.y / 0.025])
	print("particle systems: ", n)
	get_tree().quit()
