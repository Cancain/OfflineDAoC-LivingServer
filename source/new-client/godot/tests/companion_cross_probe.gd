extends Node
## Debug (bot plan phase 6, owner 2026-10-11: companions ride routes with you and zone with you): a companion hired in
## Mag Mell rides Rumdor's route to Howth behind you, over the Lough Derg -> Connacht border. The probe is added again
## by the next zone's scene (same command line) and checks the companion there: in the world, riding, close behind.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=companion_cross_probe
var v: Node
static var started := false


func _gap() -> String:
	var bots = WorldLink.bots
	if bots == null:
		return "no GameBots"
	var ids: Array = Array(bots.call("CompanionIds"))
	var out := []
	for id in ids:
		out.append("%.1f m" % (bots.call("CompanionPos", id) as Vector3).distance_to(v.player.global_position))
	return "%d companion(s) %s" % [ids.size(), out]


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	print("[xcomp] zone %s %s ride %s point %s riding %s | %s" % [v.zone.info.id, v.zone.info.name, HorseRoutes.ride.get("path", "-"),
			HorseRoutes.ride.get("i", "-"), v.player.riding, _gap()])
	if not started:
		started = true
		PlayerData.gain_xp(CombatRules.xp_for_level(5) - PlayerData.xp, false)
		for s in v.npcs.states:
			if String((s as NpcState).spawn.name) == "Rumdor":
				var at: Vector3 = (s as NpcState).pos + Vector3(2, 0, 0)
				at.y = v.zone.height_at(at.x, at.z) + 0.3
				v.player.global_position = at
		await get_tree().create_timer(0.5).timeout
		var classes := Companions.classes_for("hib", 0)
		v.companions.hire(0, 0, int(classes[0].id), "Crosser", CharacterFactory.random_look("cel_m", RandomNumberGenerator.new()), "Test")
		await get_tree().create_timer(2.0).timeout
		PlayerData.buy("HR_MagMell_Howth", "Rumdor")
	for t in 300:
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		if t % 15 == 0:
			print("[xcomp] zone %s t%d point %s riding %s | %s" % [v.zone.info.id, t, HorseRoutes.ride.get("i", "-"), v.player.riding, _gap()])
		if HorseRoutes.ride.is_empty() and t > 5:
			await get_tree().create_timer(5.0).timeout
			print("[xcomp] ride over in zone %s %s | %s" % [v.zone.info.id, v.zone.info.name, _gap()])
			get_tree().quit()
			return
