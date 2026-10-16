extends Node
## Debug: pet combat styles. A Bonedancer 50 summons a Bone Commander (template styles: Splitter, Evernight, Thor's
## Anvil, Frost Hammer, Whirling Blade, Northern Lights) and sets it on a tough monster; counts the blows that were
## styles and their names.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=bd_style_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	PlayerData.level = 50
	PlayerData.promote(ClassDb.by_name("Bonedancer"))
	PlayerData.specs["Darkness"] = 50
	PlayerData.specs["Suppression"] = 50
	PlayerData.specs["Bone Army"] = 50
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	cast._begin(ClassDb.spell(10103))
	await get_tree().create_timer(8.0).timeout
	var p := pets.pet
	print("[bd] pet ", p.spawn.name if p else "none", " L", p.level if p else 0, " styles ", p.spawn.get("styles", []) if p else [])
	if p == null:
		get_tree().quit()
		return
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 10 and (mob == null or st.level > mob.level):
			mob = st
	mob.max_hp = 99999
	mob.hp = 99999
	viewer.player.global_position = mob.pos + Vector3(12, 0.3, 0)
	p.pos = viewer.player.global_position + Vector3(1.5, 0, 0)
	await get_tree().create_timer(1.0).timeout
	if mob.view:
		viewer.npcs.select(mob.view)
	PlayerData.pet_command("attack")
	var blows := {}
	var last_hp := mob.hp
	for i in 40 * 60:
		await get_tree().physics_frame
		PlayerData.set_hp(PlayerData.max_hp)
		if mob.hp < last_hp and is_same(p.last_swing_on, mob):
			var k: String = String(p.swing_style.get("name", "plain")) if p.swing_result == "style" else "plain"
			blows[k] = int(blows.get(k, 0)) + 1
		mob.hp = 99999
		last_hp = 99999
	print("[bd] landed blows on ", mob.spawn.name, " L", mob.level, ": ", blows)
	get_tree().quit()
