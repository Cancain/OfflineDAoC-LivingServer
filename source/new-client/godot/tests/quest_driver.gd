extends Node
## Quest probe, step 2 of 3 (owner 2026-10-15: "Probe every quest script in the game and make sure they complete start to
## finish (server on, quests are serverside, figure it out)"): logs in to the running CLAUDE VERSION server with Claude's
## own test account (never the owner's) and plays every one-time quest of one realm start to finish as a GM character,
## from tools/quest_probe/plan.json (plan_quests.py): jumps to the giver, whispers the accept keyword, then each step -
## kills with /harm, whispers, interacts, hands items over, searches, uses items on the spot - and checks that the
## journal moves on, the quest finishes, and the experience, coins and items it promises arrive. One JSON line per
## quest in --out (a run can resume: quests already there are skipped). Nothing is drawn (--no-world).
##   Godot --headless --path godot res://tests/quest_driver.tscn -- --server=127.0.0.1 --account=<a> --password=<p>
##       --no-world --realm=alb --char=Qprobealb --race=Briton --plan=<plan.json> --out=<results.jsonl>
##       [--quests=20411,20412] [--limit=50] [--secs=3600]
## Every wait has a limit (a quest QUEST_SECS, the run --secs); the window quits by itself.

const QUEST_SECS := 240.0                     # one quest, start to finish
const STEP_SECS := 25.0                       # one step's action to the journal moving on
const SEE_SECS := 6.0                         # an NPC coming into view after a jump
const TARGET_IN_VIEW := 0x30                  # position action flags: the target is in sight (the server checks it for spells)
const TARGET_FLAGS := 0x6000                  # target request: in view (PlayerTargetHandler) - 0 left the server thinking it out of sight
const HIT_SPELL := 31114                      # a direct damage spell (331 DD Cold) cast by GM /cast spell
const RESPAWN_SECS := 60.0                    # waiting for a killed monster's respawn
const KILLS := 12                             # kills for one kill step (drops with a chance)
const HELPER := {"alb": "Cleric", "mid": "Healer", "hib": "Druid"}   # /spawn's group helper for "be in a group" steps
const REALM := {"alb": 1, "mid": 2, "hib": 3}

var args := {}
var plan: Array = []
var scripted: Array = []                      # the scripted (C#) quests' hand-written plans (--scripted runs them)
var objs := {}                                # oid -> {name, x, y, z, seq}
var invulnerable := false                     # just arrived in a region: the server refuses our attacks (quietly)
var seq := 0                                  # objects' arrival order (an event spawn is the newest of its name)
var region := 0
var dead := false
var msgs: Array = []                          # this quest's server lines
var out_path := ""
var done := {}                                # quest id -> true (already in the results file)
var finished_names := {}                      # lower quest name -> true (finished here: dependencies)
var class_id := 0
var level := 1
var realm := ""
var race := ""
var grouped := false                          # a /spawn helper is in the group
var STEP_RE := RegEx.create_from_string("[[]Step #([0-9]+)[]]")
var LEVEL_UP := RegEx.create_from_string("(?i)(?:raise|reached|are now)[^0-9]*level ([0-9]+)")   # a level up line


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	get_tree().create_timer(float(args.get("secs", "3600"))).timeout.connect(func():
		_log("[quest] run time over")
		get_tree().quit())
	realm = String(args.get("realm", "hib"))
	race = String(args.get("race", {"alb": "Briton", "mid": "Norseman", "hib": "Celt"}[realm]))
	out_path = String(args.get("out", "user://quest_probe.jsonl"))
	_load_plan()
	_load_done()
	if not Server.active or not Server.no_world:
		push_error("[quest] needs --server and --no-world")
		get_tree().quit()
		return
	Server.world.connect(_on_world)
	Server.login_failed.connect(func(why: String):
		_log("[quest] login failed: " + why)
		get_tree().quit(17))
	Server.start()
	get_tree().create_timer(30.0).timeout.connect(func():
		if not Server.logged:
			_log("[quest] no login answer in 30 s")
			get_tree().quit(17))
	await Server.logged_in
	await _wait(2.0)
	var c := await _character()
	if c.is_empty():
		_log("[quest] no character")
		get_tree().quit()
		return
	class_id = int(c.get("class_id", 0))
	level = int(c.get("level", 1))
	Server.enter_world(c)
	if not await _until(func(): return Server.playing and Server.me_oid != 0, 30.0):
		_log("[quest] never entered the world")
		get_tree().quit()
		return
	await _wait(3.0)
	_cmd("/gmstealth on")                             # monsters leave the GM alone; quest NPCs still talk
	await _wait(1.0)
	_cmd("/autoloot off")                             # (loot left on the ground: the backpack stays free for quest items)
	await _wait(0.6)
	await _clear_journal()
	await _run()
	_log("[quest] done")
	Server.quit_world(true)
	await _wait(4.0)
	get_tree().quit()


# ---------------------------------------------------------------- the run

func _run() -> void:
	if args.has("scripted"):
		await _run_scripted()
		return
	if args.has("collection"):
		await _run_collection(int(args.collection))
		return
	var todo := plan.filter(func(q): return int(q.realm) == int(REALM[realm]))
	if args.has("quests"):
		var want := {}
		for s in String(args.quests).split(","):
			want[int(s)] = true
		todo = todo.filter(func(q): return want.has(int(q.id)))
	todo = _ordered(todo)
	var limit := int(args.get("limit", "100000"))
	var n := 0
	for q in todo:
		if done.has(int(q.id)):
			if String(done[int(q.id)]) == "finished":           # (a resumed run: finished before)
				finished_names[String(q.name).to_lower()] = true
			continue
		if n >= limit:
			break
		n += 1
		var t0 := Time.get_ticks_msec()
		var res := await _quest(q)
		res["secs"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
		_save(res)
		if String(res.result) == "finished":
			finished_names[String(q.name).to_lower()] = true
		_log("[quest] %d %s: %s %s" % [int(q.id), q.name, res.result, res.get("why", "")])


## Repeatable XP-item turn-ins (Collection quests), a light check: a sample of this realm's, spread over its regions -
## the item made, handed to the turn-in NPC, experience expected.
func _run_collection(n: int) -> void:
	var p = JSON.parse_string(FileAccess.get_file_as_string(String(args.get("plan", ""))))
	var all: Array = (p.get("collection", []) as Array).filter(func(c): return int(c.realm) == int(REALM[realm]) and c.where != null)
	var by_region := {}
	for c in all:
		by_region.get_or_add(int(c.where.region), []).append(c)
	var pick := []
	while pick.size() < n and not by_region.is_empty():
		for reg in by_region.keys():
			if (by_region[reg] as Array).is_empty():
				by_region.erase(reg)
				continue
			pick.append((by_region[reg] as Array).pop_front())
	for c in pick.slice(0, n):
		var res := {"id": 100000 + int(c.id), "name": String(c.name), "realm": realm, "collection": true}
		if done.has(int(res.id)):
			continue
		msgs = []
		var want := clampi(int(c.min_level), 1, 49)
		if want != level:
			await _set_level(want)
		await _clear_backpack({"item_names": {}})
		_cmd("/item create %s" % c.item)
		await _until(func(): return _held(String(c.item_name)) >= 0, 4.0)
		var slot := _held(String(c.item_name))
		var xp0 := _xp()
		var lvl0 := level
		if slot < 0:
			res.result = "fail"
			res.why = "item %s could not be made" % c.item
		elif not await _go(c.where):
			res.result = "fail"
			res.why = "could not reach %s" % c.giver
		else:
			var oid := await _find(String(c.giver))
			if oid == 0:
				res.result = "fail"
				res.why = "turn-in NPC '%s' not in the world" % c.giver
			else:
				Server.client.call("Target", oid, TARGET_FLAGS)
				await _wait(0.3)
				Server.client.call("MoveItem", slot, 1000 + oid, 1)
				var got := await _until(func(): return _xp() != xp0 or level != lvl0, 5.0)
				res.result = "finished" if got else "no_reward"
				if not got:
					res.why = "gave %s to %s (level %d): no experience" % [c.item_name, c.giver, level]
		res.said = _said()
		_save(res)
		_log("[quest] turn-in %s: %s %s" % [c.name, res.result, res.get("why", "")])


## The scripted quests of this realm, each from its action list.
func _run_scripted() -> void:
	for q in scripted:
		if int(q.realm) != int(REALM[realm]):
			continue
		var key := "%s|%s" % [q.name, q.script]
		if done.has(key.hash()):
			continue
		var t0 := Time.get_ticks_msec()
		var res := await _scripted_quest(q)
		res["id"] = key.hash()
		res["secs"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
		_save(res)
		_log("[quest] script %s (%s): %s %s" % [q.name, q.script, res.result, res.get("why", "")])


func _scripted_quest(q: Dictionary) -> Dictionary:
	var res := {"name": String(q.name), "script": String(q.script), "realm": realm, "actions": [], "notes": []}
	msgs = []
	if dead:
		await _release()
	if q.has("class") and int(q["class"]) != class_id:
		await _set_class(int(q["class"]))
	if int(q.get("level", level)) != level:
		await _set_level(int(q.level))
	res["class"] = class_id
	res["level"] = level
	await _clear_backpack({"item_names": {}})
	var base := _snapshot()
	var t_end := Time.get_ticks_msec() + int(QUEST_SECS * 2000)
	for a in q.actions:
		if Time.get_ticks_msec() > t_end:
			res.result = "timeout"
			res.why = "quest time over"
			break
		var r := {"do": a["do"], "who": String(a.get("npc", a.get("name", "")))}
		var ok := await _action(q, a, r)
		res.actions.append(r)
		if not ok:
			res.result = "stuck"
			res.why = "%s %s: %s" % [a["do"], r.who, r.get("why", "")]
			break
	if not res.has("result"):
		res.result = "finished" if await _until(func(): return _journal(q) < 0 or _completed(q), 6.0) else "stuck"
		if res.result == "stuck":
			res.why = "every action done but the quest stayed in the journal"
	if q.has("unprobed") and res.result != "finished":
		res.result = "unprobed"
		res.why = String(q.unprobed)
	var now := _snapshot()
	var got := []
	for n in now.items:
		if int(now.items[n]) > int(base.items.get(n, 0)):
			got.append(n)
	res.got = {"xp": now.xp - base.xp, "copper": now.copper - base.copper, "items": got}
	if res.result == "finished" and got.size() < int(q.get("reward_count", 0)):
		res.result = "no_reward"
		res.why = "wanted %d reward items, got %d: %s" % [int(q.reward_count), got.size(), str(got)]
	var j := _journal(q)
	if j > 0:
		Server.client.call("RemoveQuest", j - 1)
	res.said = _said()
	return res


func _action(q: Dictionary, a: Dictionary, r: Dictionary) -> bool:
	if a.get("at") is Dictionary and not await _go(a.at):
		r.why = "could not jump to %s" % _pos_str(a.at)
		return false
	match String(a["do"]):
		"whisper":
			var oid := await _find(String(a.npc))
			if oid == 0:
				r.why = "not in the world"
				return false
			Server.client.call("Target", oid, TARGET_FLAGS)
			Server.client.call("Interact", oid, int(Server.entry.get("x", 0)), int(Server.entry.get("y", 0)))
			await _wait(0.7)
			_cmd("/whisper " + String(a.text))
			await _wait(1.5)
		"journal":
			if not await _until(func(): return _journal(q) >= 0, 6.0):
				r.why = "the quest was not given (level %d class %d)" % [level, class_id]
				return false
		"kill":
			var want := String(a.get("until", ""))
			var count := int(a.get("count", 6))
			var kills := 0
			while kills < count:
				var oid := await _find(String(a.name))
				if oid == 0:
					await _wait(8.0)                         # (an encounter's monster appears when you come)
					oid = await _find(String(a.name))
				if oid == 0:
					break
				Server.client.call("Target", oid, TARGET_FLAGS)
				await _wait(0.3)
				await _hit(oid)
				_cmd("/harm 100000000")
				kills += 1
				await _until(func(): return not objs.has(oid), 8.0)
				if want != "" and await _until(func(): return _held(want) >= 0, 3.0):
					break
			r.kills = kills
			if want != "" and _held(want) < 0:
				r.why = "killed %d, '%s' never given" % [kills, want] if kills > 0 else "'%s' not in the world" % a.name
				return false
		"give":
			var slot := _held(String(a.item))
			if slot < 0:
				r.why = "no '%s' in the backpack" % a.item
				return false
			var oid := await _find(String(a.npc))
			if oid == 0:
				r.why = "not in the world"
				return false
			Server.client.call("Target", oid, TARGET_FLAGS)
			await _wait(0.3)
			Server.client.call("MoveItem", slot, 1000 + oid, 1)
			await _wait(1.5)
			if _held(String(a.item)) == slot:
				r.why = "'%s' would not take '%s'" % [a.npc, a.item]
				return false
		"interact":
			var oid := await _find(String(a.npc))
			if oid == 0:
				r.why = "not in the world"
				return false
			Server.client.call("Target", oid, TARGET_FLAGS)
			Server.client.call("Interact", oid, int(Server.entry.get("x", 0)), int(Server.entry.get("y", 0)))
			await _wait(1.5)
		"wait":
			await _wait(float(a.get("secs", 2)))
	return true


## The backpack slot holding an item whose name contains `part` (any case), -1 when none.
func _held(part: String) -> int:
	for slot in Server.inv:
		if int(slot) >= 40 and int(slot) <= 79 and _inv_name(int(slot)).to_lower().contains(part.to_lower()):
			return int(slot)
	return -1


## Dependencies first (a quest after every quest it needs), then by level.
func _ordered(qs: Array) -> Array:
	# by id: one name can be several quests (a quest's version per class - "Academy Research" for sorcerers and for
	# minstrels); a dependency names a quest, any of its versions
	var by_name := {}
	for q in qs:
		by_name.get_or_add(String(q.name).to_lower(), []).append(q)
	var out := []
	var seen := {}
	var visit := func(q, f) -> void:
		if seen.has(int(q.id)):
			return
		seen[int(q.id)] = true
		for d in q.deps:
			for dq in by_name.get(String(d).to_lower(), []):
				f.call(dq, f)
		out.append(q)
	var sorted := qs.duplicate()
	sorted.sort_custom(func(a, b): return int(a.min_level) < int(b.min_level) or (int(a.min_level) == int(b.min_level) and int(a.id) < int(b.id)))
	for q in sorted:
		visit.call(q, visit)
	return out


func _quest(q: Dictionary) -> Dictionary:
	var res := {"id": int(q.id), "name": String(q.name), "realm": realm, "steps": [], "notes": []}
	msgs = []
	for d in q.deps:
		if not finished_names.has(String(d).to_lower()):
			res.result = "blocked"
			res.why = "needs '%s' (not finished in this run)" % d
			return res
	if not (q.races as Array).is_empty() and not (q.races as Array).any(func(r): return String(r).to_lower() == race.to_lower()):
		res.result = "skipped"
		res.why = "race %s only" % ", ".join(q.races)
		return res
	var t_end := Time.get_ticks_msec() + int(QUEST_SECS * 1000)
	if dead:
		await _release()
	# the class and level it is offered to
	if not (q.classes as Array).is_empty() and not (q.classes as Array).has(class_id):
		await _set_class(int(q.classes[0]))
	var want_level := clampi(maxi(level, int(q.min_level)), int(q.min_level), mini(int(q.max_level), 49))
	if want_level != level:
		await _set_level(want_level)
	res["level"] = level
	res["class"] = class_id
	await _clear_backpack(q)
	var base := _snapshot()
	# --- accept
	var acc: Dictionary = q.accept
	if acc.where == null:
		res.result = "fail"
		res.why = "giver '%s' has no spawn" % acc.npc
		return res
	if not await _go(acc.where):
		res.result = "fail"
		res.why = "could not reach giver '%s'" % acc.npc
		return res
	var giver := await _find(String(acc.npc))
	if giver == 0:
		res.result = "fail"
		res.why = "giver '%s' not in the world at %s" % [acc.npc, _pos_str(acc.where)]
		return res
	Server.client.call("Target", giver, TARGET_FLAGS)
	Server.client.call("Interact", giver, int(acc.where.x), int(acc.where.y))
	await _wait(0.8)
	if String(acc.text) != "":
		_cmd("/whisper " + String(acc.text))
	if not await _until(func(): return _journal(q) >= 0, 6.0):
		res.result = "fail"
		res.why = "giver '%s' did not give the quest (whispered '%s'; level %d class %d)" % [acc.npc, acc.text, level, class_id]
		res.said = _said()
		res.journal = Server.quests.duplicate(true)
		return res
	# --- steps
	var steps: Array = q.steps
	for i in steps.size():
		var s: Dictionary = steps[i]
		if Time.get_ticks_msec() > t_end:
			res.result = "timeout"
			res.why = "quest time over at step %d" % s.n
			break
		var st := {"n": s.n, "type": s.type, "target": s.target}
		var js := _journal_step(q)
		if _journal(q) < 0 or js > int(s.n):                # (already past it: the server moved it on by itself -
			st.auto = true                                  # an item given, a passive check, a conversation)
			res.steps.append(st)
			continue
		var ok := await _step(q, s, st, i == steps.size() - 1)
		res.steps.append(st)
		if not ok:
			res.result = "stuck"
			res.why = "step %d (%s '%s'): %s" % [s.n, s.type, s.target, st.get("why", "no progress")]
			break
	if not res.has("result"):
		res.result = "finished" if await _until(func(): return _journal(q) < 0 or _completed(q), 4.0) else "stuck"
		if res.result == "stuck":
			res.why = "every step done but the quest stayed in the journal"
	await _wait(1.0)
	_rewards(q, base, res)
	if res.result != "finished":
		var j := _journal(q)
		if j >= 0:
			Server.client.call("RemoveQuest", j - 1 if j > 0 else 0)   # (out of the journal for the next one)
	res.said = _said()
	return res


## One step: do what it asks, then wait for the journal to move on (or the quest to end on the last step).
func _step(q: Dictionary, s: Dictionary, st: Dictionary, last: bool) -> bool:
	var before := _journal_text(q)
	var n := int(s.n)
	var moved := func() -> bool:
		if _journal(q) < 0:
			return true
		var js := _journal_step(q)
		return js > n if js > 0 else _journal_text(q) != before
	var custom = s.get("custom")
	var kind := String(custom.Kind) if custom is Dictionary and custom.get("Kind") != null else ""
	var at = s.get("where")
	if at == null and custom is Dictionary and int(custom.get("Region", 0)) > 0:
		at = {"region": custom.Region, "x": custom.X, "y": custom.Y, "z": custom.Z}
	if at == null and s.get("marker") is Dictionary:
		at = {"region": s.marker.Region, "x": s.marker.X, "y": s.marker.Y, "z": s.marker.Z}
	var spawn = s.get("spawn")
	if spawn is Dictionary and String(spawn.get("Name", "")).to_lower() == String(s.target).to_lower():
		at = {"region": spawn.Region, "x": spawn.X, "y": spawn.Y, "z": spawn.Z}     # (it appears when you come)
	if at != null and not await _go(at):
		st.why = "could not jump to %s" % _pos_str(at)
		return false
	match kind:
		"travel":
			await _wait(1.0)
		"use_item":
			var slot := await _item_slot(q, String(custom.Item), st)
			if slot < 0:
				return false
			_use(slot)
		"say":
			if bool(custom.get("NightOnly", false)):
				st.note = "words work at night only"
			_cmd("/say " + String(custom.Words))
		"choose":
			var key := ""
			for k in (custom.get("Choices", {}) as Dictionary):
				key = String(k)
				break
			var oid := await _find(String(custom.Target))
			if oid == 0:
				st.why = "'%s' not in the world" % custom.Target
				return false
			Server.client.call("Target", oid, TARGET_FLAGS)
			await _wait(0.6)
			_cmd("/whisper " + key)
		"trade":
			var oid := await _find(String(custom.Target))
			if oid == 0:
				st.why = "'%s' not in the world" % custom.Target
				return false
			var input := ""
			for k in (custom.get("Trades", {}) as Dictionary):
				input = String(k)
				break
			var slot := await _item_slot(q, input, st)
			if slot < 0:
				return false
			Server.client.call("MoveItem", slot, 1000 + oid, 1)
		"has_item":
			await _item_slot(q, String(custom.Item), st)
		"interact":
			var oid := await _find(String(custom.Target))
			if oid == 0:
				st.why = "'%s' not in the world" % custom.Target
				return false
			Server.client.call("Interact", oid, int(at.x) if at else 0, int(at.y) if at else 0)
		"group":
			if not grouped:
				_cmd("/spawn " + String(HELPER[realm]))         # a temporary same-level helper joins your group
				grouped = true
				st.note = "grouped with a /spawn helper"
		"die_to", "quest":
			if not await _until(moved, 8.0):                 # (checked on the server's 5 s tick)
				st.why = "needs a %s (not probed)" % kind
				st.unprobed = true
				return false
			return true
		_:
			if not await _plain_step(q, s, st, moved):
				return false
	if await _until(moved, STEP_SECS):
		return true
	if not st.has("why"):
		st.why = "done, journal did not move on"
	return false


## The DataQuest step types (kill, deliver, interact, whisper, search, collect).
func _plain_step(q: Dictionary, s: Dictionary, st: Dictionary, moved: Callable) -> bool:
	var ty := String(s.type)
	if ty.begins_with("search"):
		# the row's search area (its centre; the marker may be on it already), the area registered by a position
		# update, then /search - "You can't do that here!" (not in the area yet): again
		if s.get("search") is Dictionary:
			var sa: Dictionary = s.search
			var z := float(sa.get("z", 0)) if float(sa.get("z", 0)) != 0.0 else (float(s.marker.Z) if s.get("marker") is Dictionary else 0.0)
			await _go({"region": sa.region, "x": sa.x, "y": sa.y, "z": z})
		await _wait(1.5)
		for attempt in 3:
			var n0 := msgs.size()
			_cmd("/search")
			await _wait(1.2)
			if not msgs.slice(n0).any(func(m): return String(m).contains("can't do that here")):
				await _until(moved, float(s.get("search", {}).get("secs", 5)) + 4.0)
				return true
			await _wait(2.0)
		st.why = "/search: \"You can't do that here!\" at the search area"
		return false
	# a kill step with an event spawn: the copy that appears for the player (the real NPC of that name may be a friendly
	# one others talk to - Ciar, Fressen, Gokstad)
	var event_kill := ty.begins_with("kill") and s.get("spawn") is Dictionary and String(s.spawn.get("Name", "")).to_lower() == String(s.target).to_lower()
	if event_kill:
		await _wait(2.5)                                # (it appears when you come)
	var oid := await _find(String(s.target), event_kill)
	if oid == 0 and ty.begins_with("kill"):
		oid = await _respawned(String(s.target))       # (killed a little before: back after its respawn time)
	if oid == 0:
		st.why = "'%s' not in the world near %s" % [s.target, _pos_str(s.where) if s.where else "the marker"]
		return false
	Server.client.call("Target", oid, TARGET_FLAGS)
	await _wait(0.4)
	if not ty.begins_with("kill"):
		await _approach(oid)                            # (roaming / not at its DB spot: "too far away to give anything")
	if ty.begins_with("kill"):
		# a step with a drop chance moves on only when the item drops (DataQuest.AdvanceQuestStep): the same kind
		# again - the next one in view, else the next spawn point - up to KILLS times
		var spots: Array = s.get("spawns", [])
		var spot := 0
		var kills := 0
		while kills < KILLS:
			# a real hit first: only the living's attackers hear of its death (GameLiving.Die -> EnemyKilled, the quest's
			# kill step); /harm alone kills without making the GM one of them
			await _hit(oid)
			_cmd("/harm 1000000")
			kills += 1
			await _until(func(): return not objs.has(oid) or moved.call(), 6.0)
			if await _until(moved, 1.5):
				break
			oid = await _find(String(s.target), event_kill)
			while oid == 0 and spot + 1 < spots.size():
				spot += 1
				await _go(spots[spot])
				oid = await _find(String(s.target))
			if oid == 0:
				oid = await _respawned(String(s.target))
			if oid == 0:
				break
			Server.client.call("Target", oid, TARGET_FLAGS)
			await _wait(0.4)
		st.kills = kills
		st.hits = msgs.filter(func(m): return String(m).begins_with("You hit") or String(m).contains("damage!")).size()
		if String(s.item) != "":
			st.drop = _has_item(q, String(s.item))
			st.drop_chance = int(s.get("drop_chance", 100))
	elif ty.begins_with("interact"):
		# a classic NPC's conversation takes a click per line (ClassicQuests.ContinueConversation) - the step counts
		# once it has been heard out: interact again while the journal stays
		for i in 6:
			Server.client.call("Interact", oid, int(Server.entry.get("x", 0)), int(Server.entry.get("y", 0)))
			if await _until(moved, 1.5):
				break
	elif ty.begins_with("whisper"):
		Server.client.call("Interact", oid, int(s.where.x) if s.where else 0, int(s.where.y) if s.where else 0)
		await _wait(0.6)
		_cmd("/whisper " + String(s.whisper))
	elif ty.begins_with("deliver") or ty.begins_with("collect"):
		var it := String(s.collect) if String(s.collect) != "" else String(s.item)
		var slot := await _item_slot(q, it, st)
		if slot < 0:
			return false
		Server.client.call("MoveItem", slot, 1000 + oid, int(Server.inv.get(slot, {}).get("count", 1)))
	return true


# ---------------------------------------------------------------- rewards

func _snapshot() -> Dictionary:
	var names := {}
	for slot in Server.inv:
		names[_inv_name(int(slot))] = int(names.get(_inv_name(int(slot)), 0)) + 1
	return {"xp": _xp(), "copper": _copper(), "items": names, "level": level}


func _rewards(q: Dictionary, base: Dictionary, res: Dictionary) -> void:
	var now := _snapshot()
	var want_money := 0
	for m in q.rewards.money:
		want_money += int(m)
	var want_xp := 0
	for x in q.rewards.xp:
		want_xp += int(x)
	var shares := 0.0
	for x in q.xp_shares:
		shares += float(x)
	var got_items := []
	for n in now.items:
		if int(now.items[n]) > int(base.items.get(n, 0)):
			got_items.append(n)
	res.got = {"xp": now.xp - base.xp, "copper": now.copper - base.copper, "items": got_items, "levels": level - int(base.level)}
	res.want = {"xp": want_xp, "xp_shares": shares, "copper": want_money, "items": q.rewards.items, "optional": q.rewards.optional}
	if res.result != "finished":
		return
	var problems := []
	if want_money > 0 and int(res.got.copper) < want_money:
		problems.append("coins: wanted %d copper, got %d" % [want_money, res.got.copper])
	if (want_xp > 0 or shares > 0.0) and int(res.got.xp) <= 0 and int(res.got.levels) <= 0:
		problems.append("experience: none received (wanted %s)" % ("%d" % want_xp if want_xp > 0 else "%.2f of a level" % shares))
	for it in q.rewards.items:
		var nm := String(q.item_names.get(String(it).to_lower(), it))
		var cls = q.rewards.class_items.get(it, {}).get(str(class_id))
		var alt := String(q.item_names.get(String(cls).to_lower(), "")) if cls != null else ""
		if not got_items.has(nm) and (alt == "" or not got_items.has(alt)):
			problems.append("reward item '%s' (%s) not received" % [nm, it])
	if not problems.is_empty():
		res.result = "no_reward"
		res.why = "; ".join(problems)


# ---------------------------------------------------------------- the world

func _on_world(kind: String, d: Dictionary) -> void:
	match kind:
		"you":
			region = int(d.region)
			objs.clear()
			invulnerable = true                          # (a fresh arrival: PvP / attack immunity for a while)
		"npc", "object":
			if not objs.has(int(d.oid)):
				seq += 1
			objs[int(d.oid)] = {"name": String(d.get("name", "")), "x": float(d.x), "y": float(d.y), "z": float(d.z),
					"seq": int(objs.get(int(d.oid), {}).get("seq", seq))}
		"remove":
			objs.erase(int(d.oid))
		"move":                                             # (zone-relative: a roaming NPC's position now)
			if objs.has(int(d.oid)) and d.has("zone"):
				var zi := Server.zone_info(int(d.zone))
				if not zi.is_empty():
					var o: Dictionary = objs[int(d.oid)]
					o.x = float(zi.get("x", 0)) * 8192.0 + float(d.x)
					o.y = float(zi.get("y", 0)) * 8192.0 + float(d.y)
					o.z = float(d.z)
		"death":
			if int(d.oid) == Server.me_oid:
				dead = true
			else:
				objs.erase(int(d.oid))                     # (its corpse stays in view a while: never a target again)
		"revive":
			if int(d.oid) == Server.me_oid:
				dead = false
		"message":
			var text := String(d.get("text", ""))
			msgs.append(text)
			if text.to_lower().contains("invulnerability timer has expired"):
				invulnerable = false
			var m := LEVEL_UP.search(text)                  # "You raise to level 6!" (a quest's or a kill's xp)
			if m:
				level = int(m.get_string(1))
		"dialog":
			if bool(d.get("quest", false)) or int(d.get("type", 0)) != 0:   # a quest offer / reward, a yes-no: yes
				Server.client.call("DialogResponse", int(d.data1), int(d.data2), int(d.data3), int(d.code), 1)
		"los":                                              # the server asks whether we see a target (spells, attacks):
			Server.client.call("LosReply", int(d.source), int(d.target), true)   # yes - nothing drawn, nothing in the way


func _xp() -> int:
	return int(Server.points.get("xp", 0))


func _level_now() -> int:
	return int(Server.info.get("level", level)) if Server.info.has("level") else level


func _copper() -> int:
	var m := Server.money
	return int(m.copper) + int(m.silver) * 100 + int(m.gold) * 10000 + int(m.platinum) * 10000000 + int(m.mithril) * 10000000000


func _inv_name(slot: int) -> String:
	return String(ItemDb.item("srv:%d" % slot).get("name", ""))


## An item name as compared: no case, no leading article ("the Flat Chert" = "Flat Chert").
static func _norm(n: String) -> String:
	var t := n.strip_edges().to_lower()
	for a in ["the ", "a ", "an ", "some "]:
		if t.begins_with(a):
			t = t.substr(a.length())
	return t


func _has_item(q: Dictionary, id_nb: String) -> bool:
	var nm := String(q.item_names.get(id_nb.to_lower(), id_nb))
	for slot in Server.inv:
		if int(slot) >= 40 and int(slot) <= 79 and _norm(_inv_name(int(slot))) == _norm(nm):
			return true
	return false


## The backpack slot holding a step's item; when the quest never handed it over, it is made (GM /item create) and noted.
func _item_slot(q: Dictionary, id_nb: String, st: Dictionary) -> int:
	if id_nb == "":
		st.why = "no item named"
		return -1
	var nm := String(q.item_names.get(id_nb.to_lower(), id_nb))
	for k in 2:
		for slot in Server.inv:
			if int(slot) >= 40 and int(slot) <= 79 and _norm(_inv_name(int(slot))) == _norm(nm):
				return int(slot)
		if k == 0:
			st.missing_item = "%s (%s) was never given - made with /item create" % [nm, id_nb]
			_cmd("/item create %s" % id_nb)
			await _until(func(): return Server.inv.keys().any(func(s): return _norm(_inv_name(int(s))) == _norm(nm)), 4.0)
	st.why = "item '%s' (%s) could not be had" % [nm, id_nb]
	return -1


func _use(slot: int) -> void:
	var e := Server.entry
	Server.client.call("UseSlot", float(e.get("x", 0)), float(e.get("y", 0)), float(e.get("z", 0)), 0.0, int(e.get("heading", 0)), true, slot, 0)


## The server said the quest is done ("You have completed the X quest!" - the journal's update can come later).
func _completed(q: Dictionary) -> bool:
	var line := "you have completed the %s quest" % String(q.name).to_lower()
	return msgs.any(func(m): return String(m).to_lower().begins_with(line))


## The journal line of this quest (its index), -1 when it isn't there.
func _journal(q: Dictionary) -> int:
	var want := String(q.name).to_lower()
	for i in Server.quests:
		var nm := String(Server.quests[i].name).to_lower()     # "Cellar Infestation (Level 1)"
		if nm == want or nm.begins_with(want + " (level"):
			return int(i)
	return -1


## The step the journal shows ("[Step #3]: ..."), 0 when it doesn't say.
func _journal_step(q: Dictionary) -> int:
	var m := STEP_RE.search(_journal_text(q))
	return int(m.get_string(1)) if m else 0


func _journal_text(q: Dictionary) -> String:
	var i := _journal(q)
	return String(Server.quests[i].text) + str(Server.quests[i].get("goals", [])) if i >= 0 else ""


## Jump to a spot (another region: wait for the world there) and tell the server we stand there.
func _go(at) -> bool:
	if at == null:
		return false
	var reg := int(at.region)
	var changing := reg != region
	_cmd("/jump to %d %d %d %d" % [int(at.x), int(at.y), int(at.z), reg])
	if changing:
		if not await _until(func(): return region == reg and Server.playing, 25.0):
			return false
		await _wait(1.5)
	else:
		await _wait(0.8)
	var zid := Server.zone_at(reg, float(at.x), float(at.y))
	Server.client.call("Position", float(at.x), float(at.y), float(at.z), 0.0, 0.0, zid, 0, true, 0, TARGET_IN_VIEW, 100, Server.me_oid)
	await _wait(0.4)
	if args.has("debug"):
		var names := []
		for oid in objs:
			names.append(String(objs[oid].name))
		_log("[debug] at region %d entry %s - %d in view: %s | said: %s" % [region, str(Server.entry.get("region")) + " " + str(int(Server.entry.get("x", 0))) + "," + str(int(Server.entry.get("y", 0))), objs.size(), ", ".join(names.slice(0, 25)), str(_said())])
	return true


## A real spell hit on the target (so the GM is one of its attackers and its death counts for the quest): the target
## said to be in view, then GM /cast spell until the server reports the hit (a resist: again), up to 3 times.
func _hit(oid: int) -> bool:
	if invulnerable:                                    # (IsAllowedToAttack: no attacks until the timer runs out)
		await _until(func(): return not invulnerable, 20.0)
		invulnerable = false
	var nm := String(objs.get(oid, {}).get("name", "")).to_lower()
	var e := Server.entry
	var zid := Server.zone_at(int(e.get("region", region)), float(e.get("x", 0)), float(e.get("y", 0)))
	for attempt in 3:
		Server.client.call("Position", float(e.get("x", 0)), float(e.get("y", 0)), float(e.get("z", 0)), 0.0, 0.0, zid, 0, true,
				int(e.get("heading", 0)), TARGET_IN_VIEW, 100, Server.me_oid)
		var n0 := msgs.size()
		_cmd("/cast spell %d" % HIT_SPELL)
		await _wait(0.3)
		if msgs.slice(n0).any(func(m): return String(m).contains("not selected a valid target") or String(m).contains("on self")):
			objs.erase(oid)                                 # (gone for the server: a corpse, out of reach)
			return false
		if await _until(func(): return msgs.slice(n0).any(func(m): return String(m).to_lower().begins_with("you hit") and String(m).to_lower().contains(nm)), 1.5):
			return true
		if args.has("debug"):
			var o: Dictionary = objs.get(oid, {})
			_log("[debug] cast %d at '%s' (oid %d, at %d,%d; me at %d,%d): %s" % [attempt, nm, oid, int(o.get("x", 0)), int(o.get("y", 0)),
					int(e.get("x", 0)), int(e.get("y", 0)), str(msgs.slice(n0))])
	return false


## Stand at an NPC's own spot (from its packets) when it isn't where we jumped: the server checks the distance to give,
## interact and whisper.
func _approach(oid: int) -> void:
	var o: Dictionary = objs.get(oid, {})
	if o.is_empty():
		return
	var e := Server.entry
	if Vector2(float(o.x) - float(e.get("x", 0)), float(o.y) - float(e.get("y", 0))).length() > 100.0:
		await _go({"region": region, "x": o.x, "y": o.y, "z": o.z})


## A monster killed a little before (a named one with a single spawn): waits up to RESPAWN_SECS for it.
func _respawned(name: String) -> int:
	var t := Time.get_ticks_msec() + int(RESPAWN_SECS * 1000)
	while Time.get_ticks_msec() < t:
		var oid := await _find(name)
		if oid != 0:
			return oid
	return 0


## The nearest object of that name in view (waiting a little for it to come into view).
func _find(name: String, newest := false) -> int:
	var lname := name.to_lower()
	var best := [0]                                     # (a lambda gets copies of locals: the answer goes in an array)
	await _until(func():
		var e := Server.entry
		var bd := INF
		for oid in objs:
			if String(objs[oid].name) == name:            # (exact, as DataQuest matches: "dragon ant queen" is not
														# the "Dragon Ant Queen" standing near it)
				var d := Vector2(float(objs[oid].x) - float(e.get("x", 0)), float(objs[oid].y) - float(e.get("y", 0))).length()
				if newest:
					d = -float(objs[oid].get("seq", 0))     # (the one that just appeared)
				if d < bd:
					bd = d
					best[0] = int(oid)
		return best[0] != 0, SEE_SECS)
	return best[0]


func _set_class(cid: int) -> void:
	Server.client.call("Target", Server.me_oid, TARGET_FLAGS)
	await _wait(0.4)
	_cmd("/player class %d" % cid)
	await _wait(1.5)
	class_id = cid


func _set_level(n: int) -> void:
	Server.client.call("Target", Server.me_oid, TARGET_FLAGS)
	await _wait(0.4)
	_cmd("/player level %d" % n)
	await _wait(2.0)
	level = n


## Room for the quest's items and rewards (an epic's six pieces): every backpack item this quest doesn't name is
## destroyed (rewards and loot of the quests before).
func _clear_backpack(q: Dictionary) -> void:
	var keep := {}
	for k in q.item_names:
		keep[String(q.item_names[k])] = true
	var gone := 0
	for slot in Server.inv.keys():
		if int(slot) >= 40 and int(slot) <= 79 and not keep.has(_inv_name(int(slot))):
			Server.client.call("DestroyItem", int(slot))
			gone += 1
			await _wait(0.05)
	if gone > 0:
		await _wait(0.6)


## Quests left in the journal by an earlier run: abandoned, the highest place first.
func _clear_journal() -> void:
	var keys := Server.quests.keys()
	keys.sort()
	keys.reverse()
	keys = keys.filter(func(i): return int(i) > 0)     # (0: the personal task line)
	for i in keys:
		Server.client.call("RemoveQuest", int(i) - 1)
		await _wait(0.5)
	if not keys.is_empty():
		_log("[quest] abandoned %d quests left from before: %s" % [keys.size(), str(keys)])


func _release() -> void:
	_cmd("/release")
	await _until(func(): return not dead, 15.0)
	await _wait(2.0)
	_cmd("/gmstealth on")


func _cmd(text: String) -> void:
	Server.command(text)


func _said() -> Array:
	return msgs.slice(maxi(0, msgs.size() - 12))


# ---------------------------------------------------------------- setup

func _character() -> Dictionary:
	var want := String(args.get("char", "Qprobe" + realm))
	var c := _find_char(want)
	if not c.is_empty():
		return c
	var rid := int(Server.RACE_BY_NAME.get(race, 0))
	var classes: Array = Server.classes_for(realm, rid, false)
	var cid := int(classes[0][0]) if classes.size() > 0 else 0
	_log("[quest] creating %s %s class %d" % [want, race, cid])
	var err := Server.create_character(realm, race, false, cid, want, {})
	if err != "":
		_log("[quest] create failed: " + err)
		return {}
	await Server.created
	await _wait(2.0)
	Server.request_characters(realm)
	await _wait(2.0)
	return _find_char(want)


func _find_char(char_name: String) -> Dictionary:
	for c in Server.characters_in(realm):
		if String(c.name).to_lower() == char_name.to_lower():
			return c
	return {}


func _load_plan() -> void:
	var p = JSON.parse_string(FileAccess.get_file_as_string(String(args.get("plan", ""))))
	plan = p.quests if p is Dictionary else []
	scripted = p.get("scripted", []) if p is Dictionary else []


func _load_done() -> void:
	if not FileAccess.file_exists(out_path):
		return
	for line in FileAccess.get_file_as_string(out_path).split("\n"):
		var r = JSON.parse_string(line) if line.strip_edges() != "" else null
		if r is Dictionary and r.has("id"):
			done[int(r.id)] = String(r.get("result", ""))


func _save(res: Dictionary) -> void:
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(res))
	f.close()


func _log(t: String) -> void:
	print(t)


func _pos_str(at) -> String:
	return "region %d %d %d" % [int(at.region), int(at.x), int(at.y)] if at is Dictionary else "?"


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, secs: float) -> bool:
	var t := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < t:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
	return bool(cond.call())
