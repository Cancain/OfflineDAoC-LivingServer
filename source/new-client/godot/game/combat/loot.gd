class_name Loot
extends Node
## Monster drops and items on the ground (owner 2026-10-10).
##   Drops: content/loot/loot.json (pipeline/build_loot.py): per monster name the Uthgard bestiary's measured coin
##   chance (none known: the old server's LootGeneratorMoney, which always drops) and item chances, the old DB's loot
##   templates and one-time drops (LootOTD: once per character, from its minimum level). Coins: the old server's
##   formula - (level + 1)^3 / 8 + 2, plus up to half again, x money_drop 1.
##   AUTO LOOT (a QOL addition, "1.65 EXCEPTIONS MADE.txt"; the old OfflineDAoC's /autoloot, on by default for every
##   character, Options > INTERFACE - the /autoloot command is gone, owner 2026-10-10 bot plan phase 1): coins and items go straight to you - "You pick up 3 copper.",
##   "You get a Petrified Branch and put it in your backpack."; a full backpack leaves that item on the ground, as the
##   old server did ("Your backpack is full. You must drop something first."). Auto loot off: everything lies at the
##   monster's feet, as in the original, until you click it.
##   Ground: what you drag out of your backpack onto the world lands at your feet ("You drop the X on the ground!");
##   equipped items and no-drop items can't be dropped. Anything on the ground is gone after 3 minutes
##   (world_item_decay_time 180000).

const DATA := "res://content/loot/loot.json"
const MONEY_MODEL := 488                      # "bag of coins" (LootGeneratorMoney)
const PICK_LAYER := 1 << 11
const DECAY_S := 180.0
const REACH_M := 6.0

static var _data := {}
var viewer: Node
var _ground: Array = []                       # {node, id, money, until}
var _holder: Node3D


static func data() -> Dictionary:
	if _data.is_empty():
		var p = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
		_data = p if p is Dictionary else {"drops": {}, "items": {}}
	return _data


static func item(id: String) -> Dictionary:
	return (data().get("items", {}) as Dictionary).get(id, {})


static func autoloot() -> bool:
	return bool(PlayerData.character.get("autoloot", true))


## The options toggle (the old server's messages).
static func set_autoloot(on: bool) -> void:
	PlayerData.character["autoloot"] = on
	if Server.active:
		# the server's own autoloot (its &autoloot command: GamePlayer.Autoloot) - the toggle only changed ours, which
		# the server game doesn't use (owner 2026-10-15 UI audit); the server answers with its message
		Server.command("/autoloot %s" % ("on" if on else "off"))
		return
	PlayerData.save_character()
	PlayerData.message.emit("Your autoloot is on. You will now attempt to automatically loot anything that drops in your area." if on
			else "Your autoloot is off. You will no longer attempt to automatically loot anything that drops in your area.", "system")


func setup(v: Node) -> void:
	viewer = v
	_holder = Node3D.new()
	_holder.name = "GroundItems"
	(viewer as Node).add_child(_holder)


# --- drops --------------------------------------------------------------------------------------------------------

func on_kill(st: NpcState) -> void:
	var d: Dictionary = (data().get("drops", {}) as Dictionary).get(String(st.spawn.name).to_lower(), {})
	var at: Vector3 = st.pos
	var coins = d.get("coins") if not d.is_empty() else null
	if coins == null or randf() * 100.0 < float(coins):
		_drop_money(money_for(int(st.level)), at)
	for e in d.get("items", []):
		if randf() * 100.0 < float(e[1]):
			_drop_item(String(e[0]), at)
	var got: Dictionary = PlayerData.character.get("otd_done", {})
	for e in d.get("otd", []):                        # LootOTD: once per character, from its minimum level
		var id := String(e[0])
		if PlayerData.level >= int(e[1]) and not got.has(id) and not ItemDb.item(id).is_empty():
			got[id] = true
			PlayerData.character["otd_done"] = got
			_drop_item(id, at)


## LootGeneratorMoney: (level + 1)^3 / 8 + 2 copper, plus up to half that again.
static func money_for(level: int) -> int:
	var lvl := maxi(level + 1, 1)
	var least := 2 + ((lvl * lvl * lvl) >> 3)
	return int((least + randi_range(0, least >> 1)) * float(data().get("money", {}).get("money_drop", 1.0)))


func _drop_money(copper: int, at: Vector3) -> void:
	if copper <= 0:
		return
	if autoloot():
		_take_money(copper)
	else:
		_place("", copper, at)


func _drop_item(id: String, at: Vector3) -> void:
	if ItemDb.item(id).is_empty():
		return
	if autoloot() and _take_item(id):
		return
	_place(id, 0, at)                                   # auto loot off, or the backpack is full


func _take_money(copper: int) -> void:
	PlayerData.set_copper(PlayerData.total_copper() + copper)
	PlayerData.message.emit("You pick up %s." % PlayerData.money_string(copper), "loot")


func _take_item(id: String) -> bool:
	if not PlayerData.give_item(id, "", true):
		PlayerData.message.emit("Your backpack is full. You must drop something first.", "system")
		return false
	PlayerData.message.emit("You get %s and put it in your backpack." % article(String(ItemDb.item(id).get("name", id))), "loot")
	return true


static func article(item_name: String) -> String:
	if item_name == "":
		return item_name
	return ("an " if "aeiouAEIOU".contains(item_name.left(1)) else "a ") + item_name


# --- the ground ---------------------------------------------------------------------------------------------------

## Drag from the backpack onto the world (not on an NPC): the item lands at your feet.
func drop_from_inventory(slot: int) -> void:
	var e := PlayerData.entry(slot)
	if e.is_empty():
		return
	if not PlayerData.is_backpack(slot):
		return                                              # equipped: take it off first (old server)
	var it := ItemDb.item(String(e.id))
	if int(it.get("isdropable", 1)) == 0:
		PlayerData.message.emit("You can not drop this item!", "system")
		return
	var count := int(e.get("count", 1))
	PlayerData.inventory.erase(slot)
	PlayerData.inventory_changed.emit()
	PlayerData.save_character()
	var p: Vector3 = viewer.player.global_position + (-viewer.player.global_transform.basis.z) * 0.8
	var node := _place(String(e.id), 0, Vector3(p.x, viewer.player.global_position.y, p.z))
	if node:
		node.set_meta("count", count)
	PlayerData.message.emit("You drop the %s on the ground!" % String(it.get("name", "item")), "system")


func _place(id: String, copper: int, at: Vector3) -> Node3D:
	# what lies there: a weapon or shield shows itself; anything else (armour, jewellery, coins...) is the brown bag
	# (owner 2026-10-10: the old OfflineDAoC's ground drops; the client has world models only for those)
	var it := ItemDb.item(id) if id != "" else {}
	var ot := int(it.get("object_type", 0))
	var model := int(it.get("model", MONEY_MODEL)) if (ot >= 1 and ot <= 28) or ot == 42 else MONEY_MODEL
	var holder := Node3D.new()
	_holder.add_child(holder)
	var spread := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) if id != "" or copper > 0 else Vector3.ZERO
	var spot := at + spread
	if viewer.zone and viewer.zone.has_method("height_at"):
		spot.y = maxf(spot.y, float(viewer.zone.height_at(spot.x, spot.z, spot.y)))   # (in a city: the floor under it)
	holder.global_position = spot
	var m := WeaponModels.make_world(model)
	if m == null:
		m = WeaponModels.make_world(MONEY_MODEL)
	if m:
		holder.add_child(m)
	var body := StaticBody3D.new()                          # what a click finds
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	shape.position.y = 0.2
	body.add_child(shape)
	holder.add_child(body)
	body.set_meta("ground", holder)
	_ground.append({"node": holder, "id": id, "money": copper, "until": Time.get_ticks_msec() / 1000.0 + DECAY_S})
	return holder


## A left click on something lying on the ground picks it up (in reach). True when the click hit one.
func click(screen_pos: Vector2) -> bool:
	var cam: Camera3D = viewer.player.camera
	var from := cam.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 60.0, PICK_LAYER)
	var hit := (viewer as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider.has_meta("ground"):
		return false
	var holder: Node3D = hit.collider.get_meta("ground")
	for g in _ground:
		if g.node != holder:
			continue
		if holder.global_position.distance_to(viewer.player.global_position) > REACH_M:
			PlayerData.message.emit("The %s is too far away to pick up!" % ("bag of coins" if String(g.id) == "" else String(ItemDb.item(String(g.id)).get("name", "item"))), "system")
			return true
		if String(g.id) == "":
			_take_money(int(g.money))
		else:
			var count := int(holder.get_meta("count", 1))
			if not _take_item(String(g.id)):
				return true
			if count > 1:
				var s := PlayerData.find_item(String(g.id))
				if s >= 0:
					PlayerData.inventory[s]["count"] = count
					PlayerData.inventory_changed.emit()
		holder.queue_free()
		_ground.erase(g)
		return true
	return false


func _process(_delta: float) -> void:
	if _ground.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for g in _ground.duplicate():
		if now >= float(g.until):
			if is_instance_valid(g.node):
				(g.node as Node).queue_free()
			_ground.erase(g)
