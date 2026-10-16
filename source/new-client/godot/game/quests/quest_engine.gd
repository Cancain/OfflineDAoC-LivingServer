class_name QuestEngine
extends Node
## The classic quests (QuestDb), run the way the old server's DataQuest ran them - its rules, read from its code and
## rebuilt here (no old code): a giver offers its quests' descriptions on interact; whispering (clicking) the accept
## keyword starts the quest and shows step 1's source text; each step ends by its type -
##   kill / kill_finish: kill the target (a step item with a chance "drops" or the kill doesn't count),
##   deliver / collect (+ _finish): hand the target the step's item (drag it onto the NPC),
##   interact / interact_finish: right-click the target, whisper / whisper_finish: say its advance keyword,
##   search / search_finish: /search inside the step's area for its seconds.
## Advancing gives the step's item (deliveries get theirs when the step begins), the step's XP / money, and shows the
## next step's source text; finishing gives the last step's XP / money and the final reward items, then the finish text
## and "You have completed the <quest> quest!". The classic additions (custom steps: use an item at a place, reach a
## place, hold an item, finish other quests, trade with an NPC, choose a reward, say words of power, die to an NPC;
## re-issued lost step items; granted items) work the old ClassicQuests way. Quest XP isn't multiplied by the realm XP
## rate (DataQuest ForceGainExperience).

var viewer: Node
var _tick := 1.0
var _search_left := 0.0
var _search_quest := ""
var _cooldowns := {}                    # "quest:step:what" -> seconds left (re-issues, grants, event respawns)
var _events := {}                       # "quest:step" -> [NpcState, ...] event monsters out for this player
var _event_left := {}                   # "quest:step" -> seconds until they leave


func setup(v: Node) -> void:
	viewer = v
	PlayerData.item_used.connect(on_use_item)
	PlayerData.search_requested.connect(search)
	PlayerData.said.connect(on_say)


# --- the rules --------------------------------------------------------------------------------------------------

## DataQuest.CheckQuestQualification: level range, class, race, not doing it, not done (max once), dependencies done.
func qualifies(q: Dictionary) -> bool:
	if PlayerData.level < int(q.min) or PlayerData.level > int(q.max):
		return false
	var classes: Array = q.get("classes", [])
	if not classes.is_empty() and not (PlayerData.class_id() in classes.map(func(c): return int(c))):
		return false
	var races: Array = q.get("races", [])
	if not races.is_empty():
		var race := String(PlayerData.character.get("race", "")).replace(" ", "").to_lower()
		if not races.any(func(r): return String(r).replace(" ", "").to_lower() == race):
			return false
	var id := str(int(q.id))
	if PlayerData.quests.has(id) or int(PlayerData.quests_done.get(id, 0)) >= int(q.get("max_count", 1)):
		return false
	for dep in q.get("depends", []):
		if not _finished_named(String(dep)):
			return false
	return true


func _finished_named(quest_name: String) -> bool:
	for id in PlayerData.quests_done:
		if String(QuestDb.quest(id).get("name", "")).to_lower() == quest_name.to_lower():
			return true
	return false


func step_of(id: String) -> Dictionary:
	var q := QuestDb.quest(id)
	var n := int(PlayerData.quests.get(id, {}).get("step", 0))
	var steps: Array = q.get("steps", [])
	return steps[n - 1] if n >= 1 and n <= steps.size() else {}


func _is_finish(st: Dictionary) -> bool:
	return String(st.get("type", "")).ends_with("_finish")


## Text the old server personalised (BehaviourUtils): <Player> / {Player}, <Class>, <Race>.
func _text(t: String) -> String:
	t = t.replace("<Player>", PlayerData.display_name()).replace("{Player}", PlayerData.display_name())
	t = t.replace("<Class>", String(ClassDb.cls(PlayerData.class_id()).get("name", ""))).replace("<Race>", String(PlayerData.character.get("race", "")))
	# walkthrough leftovers in the dialogue ("Dialog box: Will you ...?") are a note, not speech
	var i := t.find("Dialog box:")
	return t.substr(0, i).strip_edges() if i >= 0 else t


## An NPC's words: the dialogue window for realm NPCs, a say line in chat for monsters (the old server's
## CT_Say / popup split).
func _say(n: Npc, text: String) -> void:
	if text.strip_edges() == "":
		return
	if n and int(n.spawn.realm) == 0:
		PlayerData.message.emit("%s says, \"%s\"" % [String(n.spawn.name), _text(text)], "npc")
	elif n:
		# several lines from one NPC at one moment (a delivery's thanks, then the quest's finish text; a trainer's
		# greeting and its quest offers) stack up in the window itself (NpcDialog.say)
		viewer.ui.npc_dialog.say(String(n.spawn.id), String(n.spawn.name), _text(text))
	else:
		PlayerData.message.emit(_text(text), "system")


var _said_frame := -1
var _said_npc := ""
var _said_text := ""


# --- the hooks ----------------------------------------------------------------------------------------------------

## A right-click on an NPC: quest offers (the description of every quest it can give you), then the steps of your
## quests that end at it, the classic interact steps, and lost step items re-issued. True when it said anything.
func on_interact(n: Npc) -> bool:
	var who := String(n.spawn.name)
	var said := false
	var offers := []
	for q in QuestDb.by_giver(who):
		if qualifies(q) and String(q.description) != "":
			offers.append(String(q.description))
	if not offers.is_empty():
		_say(n, "\n\n".join(offers))
		said = true
	for id in PlayerData.quests.keys():
		var st := step_of(id)
		if st.is_empty():
			continue
		var custom: Dictionary = st.get("custom", {})
		if String(custom.get("kind", "")) == "interact" and String(custom.get("target", "")).to_lower() == who.to_lower():
			_advance_by_script(id, n)
			said = true
			continue
		if String(st.target).to_lower() != who.to_lower():          # quest data capitalises names the DB writes in lower case
			_reissue(id, st, n)
			continue
		match String(st.type):
			"interact":
				_say(n, String(st.target_text))
				_advance(id, n)
				said = true
			"interact_finish":
				_finish(id, n)
				said = true
			_:
				if String(st.target_text) != "":
					_say(n, String(st.target_text))
					said = true
		_reissue(id, st, n)
	return said


## A clicked / whispered keyword: a classic "choose your reward", the walkthrough's reply, a quest's accept keyword,
## a whisper step's advance keyword.
## Words compared as typed words are: no surrounding spaces, no closing . ! ?, any case.
func _norm(s: String) -> String:
	return s.strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?").to_lower()


func on_keyword(n: Npc, word: String) -> void:
	var who := String(n.spawn.name)
	var key := word.strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?")
	for id in PlayerData.quests.keys():
		var custom: Dictionary = step_of(id).get("custom", {})
		if String(custom.get("kind", "")) == "choose" and String(custom.get("target", "")).to_lower() == who.to_lower():
			var choices: Dictionary = custom.get("choices", {})
			for c in choices:
				if _norm(String(c)) == _norm(key):
					# a reward with no item data anywhere (OWNER ATTENTION 13) doesn't hold the quest up
					if ItemDb.item(String(choices[c])).is_empty() or PlayerData.give_item(String(choices[c]), who):
						_advance_by_script(id, n)
					return
	var reply := ""
	var lines := QuestDb.chat(who)
	for k in lines:
		if _norm(String(k)) == _norm(key):
			reply = String(lines[k])
	if reply != "":
		_say(n, reply)
	for q in QuestDb.by_giver(who):
		if String(q.accept) != "" and _norm(String(q.accept)) == _norm(key) and qualifies(q):
			_start(q, n)
			return
	for id in PlayerData.quests.keys():
		var st := step_of(id)
		# the step's words are compared the way yours are (no closing . ! ?): "May I have a perfect glass orb?"
		var want := String(st.get("advance", "")).strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?")
		if String(st.get("target", "")).to_lower() == who.to_lower() and want.to_lower() == key.to_lower() and want != "":
			if String(st.type) == "whisper":
				_advance(id, n)
			elif String(st.type) == "whisper_finish":
				_finish(id, n)


## An item handed to an NPC (dragged onto it). True when a quest took it.
func on_give(n: Npc, slot: int) -> bool:
	var who := String(n.spawn.name)
	var e := PlayerData.entry(slot)
	if e.is_empty():
		return false
	var item_id := String(e.id).to_lower()
	for id in PlayerData.quests.keys():
		var st := step_of(id)
		var custom: Dictionary = st.get("custom", {})
		if String(custom.get("kind", "")) == "trade" and String(custom.get("target", "")).to_lower() == who.to_lower():
			var trades: Dictionary = custom.get("trades", {})
			for want in trades:
				if String(want).to_lower() == item_id:
					PlayerData.take_one(slot)
					if String(trades[want]) != "":
						PlayerData.give_item(String(trades[want]), who)
					_advance_by_script(id, n)
					return true
		if String(st.get("target", "")).to_lower() != who.to_lower():
			continue
		var q := QuestDb.quest(id)
		if PlayerData.level < int(q.min) or PlayerData.level > int(q.max):
			continue
		var wanted := String(st.collect).to_lower()
		if wanted == "" or not item_id.contains(wanted):
			wanted = String(st.step_item).to_lower()
			if wanted == "" or not item_id.contains(wanted) or not String(st.type).begins_with("deliver"):
				continue
		match String(st.type):
			"deliver", "collect":
				_say(n, String(st.target_text))
				if _advance(id, n):
					PlayerData.take_one(slot)
					PlayerData.message.emit("You give the %s to %s." % [String(ItemDb.item(String(e.id)).get("name", "item")), who], "system")
				return true
			"deliver_finish", "collect_finish":
				_say(n, String(st.target_text))
				PlayerData.take_one(slot)
				PlayerData.message.emit("You give the %s to %s." % [String(ItemDb.item(String(e.id)).get("name", "item")), who], "system")
				if not _finish(id, n):
					PlayerData.give_item(String(e.id))           # the finish failed (backpack full): keep the item
				return true
	return false


## A monster the player killed: kill steps and the classic kill-task drops.
func on_kill(st: NpcState) -> void:
	var who := String(st.spawn.name)
	for id in PlayerData.quests.keys():
		var s := step_of(id)
		for drop in s.get("custom", {}).get("drops", []):
			if String(drop.get("Mob", "")).to_lower() == who.to_lower() and randf() * 100.0 < float(drop.get("Chance", 100)):
				var it := ItemDb.item(String(drop.Item))
				if PlayerData.give_item(String(drop.Item)):
					PlayerData.message.emit("You take the %s from %s." % [String(it.get("name", "")), combat_name(st)], "loot")
		if String(s.get("target", "")).to_lower() != who.to_lower():
			continue
		if String(s.type) == "kill":
			if String(s.target_text) != "":
				PlayerData.message.emit("%s says, \"%s\"" % [who, _text(String(s.target_text))], "npc")
			_advance(id, null)
		elif String(s.type) == "kill_finish":
			_finish(id, null)


func combat_name(st: NpcState) -> String:
	var n := String(st.spawn.name)
	return ("the " + n) if n.length() > 0 and n[0] == n[0].to_lower() else n


## The player died to something (a classic die_to step: a willing sacrifice).
func on_player_died(killer: String) -> void:
	for id in PlayerData.quests.keys():
		var custom: Dictionary = step_of(id).get("custom", {})
		if String(custom.get("kind", "")) == "die_to" and String(custom.get("target", "")).to_lower() == killer.to_lower():
			_advance_by_script(id, null)


## An item used (U / quickbar): a classic use_item step at its place.
func on_use_item(item_id: String) -> void:
	for id in PlayerData.quests.keys():
		var custom: Dictionary = step_of(id).get("custom", {})
		if String(custom.get("kind", "")) != "use_item" or String(custom.get("item", "")).to_lower() != item_id.to_lower():
			continue
		if not _in_place(custom):
			PlayerData.message.emit("Nothing happens. This is not the place to use the %s." % String(ItemDb.item(item_id).get("name", "item")), "system")
			continue
		if bool(custom.get("consume", false)):
			var s := PlayerData.find_item(item_id)
			if s >= 0:
				PlayerData.take_one(s)
		_advance_by_script(id, null)
		return


## Words spoken aloud (/say): a classic say step at its place (some only at night).
func on_say(text: String) -> void:
	var spoken := _words(text)
	for id in PlayerData.quests.keys():
		var custom: Dictionary = step_of(id).get("custom", {})
		if String(custom.get("kind", "")) != "say" or not spoken.contains(_words(String(custom.get("words", "")))):
			continue
		if not _in_place(custom):
			PlayerData.message.emit("Nothing answers. The words must be spoken at the right place.", "system")
			continue
		if bool(custom.get("nightonly", false)) and viewer.sky and not viewer.sky.is_night():
			PlayerData.message.emit("Nothing answers. The words of power work only at night.", "system")
			continue
		_advance_by_script(id, null)


func _words(t: String) -> String:
	var re := RegEx.create_from_string("[a-z0-9']+")
	return " ".join(re.search_all(t.to_lower()).map(func(m): return m.get_string()))


## /search: inside the current step's search area it takes the area's seconds ("Searching ..."); then a search step
## advances (its item may have a chance: "You fail to find anything!") and a search_finish step finishes.
func search() -> void:
	if _search_left > 0.0:
		return
	for id in PlayerData.quests.keys():
		var st := step_of(id)
		var area: Dictionary = st.get("search", {})
		if area.is_empty() or not String(st.type).begins_with("search") or not _in_area(area):
			continue
		_search_quest = id
		_search_left = maxf(1.0, float(area.get("seconds", 5)))
		PlayerData.message.emit("Searching ...", "system")
		viewer.ui.show_cast("SEARCHING", 0.0)
		return
	PlayerData.message.emit("You can't find anything to search here.", "system")


func _process(delta: float) -> void:
	if viewer == null or viewer.player == null:
		return
	if _search_left > 0.0:
		var area: Dictionary = step_of(_search_quest).get("search", {})
		if area.is_empty() or viewer.player.velocity.length() > 0.2 or viewer.player.dead:
			_search_left = 0.0
			viewer.ui.show_cast("", -1.0)
			PlayerData.message.emit("You stop searching.", "system")
		else:
			var total := maxf(1.0, float(area.get("seconds", 5)))
			_search_left -= delta
			viewer.ui.show_cast("SEARCHING", 1.0 - _search_left / total)
			if _search_left <= 0.0:
				viewer.ui.show_cast("", -1.0)
				var st := step_of(_search_quest)
				if String(st.type) == "search_finish":
					_finish(_search_quest, null)
				elif not _advance(_search_quest, null):
					PlayerData.message.emit("You fail to find anything!", "system")
	for k in _cooldowns.keys():
		_cooldowns[k] = float(_cooldowns[k]) - delta
		if float(_cooldowns[k]) <= 0.0:
			_cooldowns.erase(k)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	_events_tick()
	for id in PlayerData.quests.keys():
		var st := step_of(id)
		if st.is_empty():
			continue
		_grants(id, st)
		var custom: Dictionary = st.get("custom", {})
		if custom.is_empty():
			continue
		if bool(custom.get("give", false)) and String(custom.get("item", "")) != "" and PlayerData.find_item(String(custom.item)) < 0:
			var key := "%s:%d:give" % [id, int(PlayerData.quests[id].step)]
			if not _cooldowns.has(key):
				_cooldowns[key] = 60.0
				PlayerData.give_item(String(custom.item))
		var done := false
		match String(custom.get("kind", "")):
			"travel": done = _in_place(custom)
			"has_item": done = String(custom.get("item", "")) != "" and PlayerData.find_item(String(custom.item)) >= 0
			"quest":
				var names := Array(String(custom.get("quest", "")).split("|", false))
				var need := int(custom.get("count", 0)) if int(custom.get("count", 0)) > 0 else names.size()
				done = names.size() > 0 and names.filter(func(nm): return _finished_named(String(nm).strip_edges())).size() >= need
		if done:
			_advance_by_script(id, null)


# --- quest flow -----------------------------------------------------------------------------------------------------

func _start(q: Dictionary, n: Npc) -> void:
	var id := str(int(q.id))
	var steps: Array = q.get("steps", [])
	var first: Dictionary = steps[0] if not steps.is_empty() else {}
	# a delivery step's item is handed over when the step begins (DataQuest's own rule for StepItemTemplates)
	if String(first.get("type", "")).begins_with("deliver") and String(first.get("step_item", "")) != "":
		if PlayerData.free_slots() < 1:
			PlayerData.message.emit("Your backpack is full!", "system")
			return
	PlayerData.quests[id] = {"step": 1}
	if not steps.is_empty():
		_say(n, String(first.get("source_text", "")))
		if String(first.get("type", "")).begins_with("deliver") and String(first.get("step_item", "")) != "":
			PlayerData.give_item(String(first.step_item), String(n.spawn.name) if n else "")
	_changed()


## DataQuest.AdvanceQuestStep: the step's own item (not for deliveries; kill / search ones can carry a chance and the
## step doesn't advance when it fails), the next step's delivery item, the step's XP and money, then the next step's
## source text.
func _advance(id: String, obj: Npc) -> bool:
	var q := QuestDb.quest(id)
	var steps: Array = q.get("steps", [])
	var n := int(PlayerData.quests[id].step)
	var cur: Dictionary = steps[n - 1]
	var give := []
	if String(cur.step_item) != "" and not String(cur.type).begins_with("deliver"):
		if String(cur.type) in ["kill", "kill_finish", "search", "search_finish"] and int(cur.get("step_chance", 0)) > 0:
			if randf() * 100.0 >= float(cur.step_chance):
				return false
		give.append(String(cur.step_item))
	if n < steps.size():
		var nxt: Dictionary = steps[n]
		if String(nxt.type).begins_with("deliver") and String(nxt.step_item) != "":
			give.append(String(nxt.step_item))
	if PlayerData.free_slots() < give.size():
		PlayerData.message.emit("You don't have enough inventory space to advance this quest.  You need %d free slot(s)!" % give.size(), "system")
		return false
	for item_id in give:
		PlayerData.give_item(item_id, String(obj.spawn.name) if obj else "")
	_reward(step_xp(cur), int(cur.get("money", 0)))
	PlayerData.quests[id].step = n + 1
	if n < steps.size():
		_say(obj, String(steps[n].get("source_text", "")))
	_changed()
	return true


## DataQuest.FinishQuest: the last step's XP and money, the final reward items (room needed), then done.
func _finish(id: String, obj: Npc) -> bool:
	var q := QuestDb.quest(id)
	var steps: Array = q.get("steps", [])
	var n := int(PlayerData.quests[id].step)
	var cur: Dictionary = steps[n - 1] if n >= 1 and n <= steps.size() else {}
	var rewards: Array = q.get("final_rewards", []).filter(func(r): return not ItemDb.item(String(r)).is_empty())
	if PlayerData.free_slots() < rewards.size():
		_say(obj, "Your inventory does not have enough space to finish this quest!")
		return false
	_reward(step_xp(cur), int(cur.get("money", 0)))
	for r in rewards:
		PlayerData.give_item(String(r))
	PlayerData.quests.erase(id)
	PlayerData.quests_done[id] = int(PlayerData.quests_done.get(id, 0)) + 1
	PlayerData.message.emit("You have completed the %s quest!" % String(q.name), "system")
	if String(q.get("finish_text", "")) != "" and not _giver_line(q, String(q.finish_text), obj):
		_say(obj, String(q.finish_text))
	_changed()
	return true


## Data fix (Lough Derg, "Please Deliver!"): some old rows' FinishText repeats a line of the giver's own dialogue
## ("Deliver this letter to Dirmyg...") - spoken by the NPC the quest ends at, it reads wrong, so it is left out there.
func _giver_line(q: Dictionary, text: String, obj: Npc) -> bool:
	if obj == null or String(obj.spawn.name) == String(q.giver):
		return false
	var t := text.strip_edges()
	for v in QuestDb.chat(String(q.giver)).values():
		if String(v).strip_edges() == t:
			return true
	for st in q.get("steps", []):
		if String(st.get("source_text", "")).strip_edges() == t:
			return true
	return false


## A quest finished by a system outside the steps (the companions' courier quest: hiring your first companion).
func finish_scripted(id: String) -> void:
	if PlayerData.quests.has(id):
		_finish(id, null)


## ClassicQuests' scripted triggers: finish on a finish step, else advance.
func _advance_by_script(id: String, obj: Npc) -> bool:
	return _finish(id, obj) if _is_finish(step_of(id)) else _advance(id, obj)


## A step's experience. Period quests paid by your level (pipeline/build_quest_xp.py: Allakhazam 2002-2004 figures are
## exact multiples of a same-level kill): xp_n x xp_for_living(level) below the step's cap level, xp_n / 1.1 x
## xp_for_living(cap) from it. A step without xp_n pays its fixed amount.
static func step_xp(st: Dictionary) -> int:
	if not st.has("xp_n"):
		return int(st.get("xp", 0))
	var t: Array = CombatRules.r().get("xp_for_living", [5])
	var cap := int(st.get("xp_cap", 50))
	var lv := PlayerData.level
	if lv < cap:
		return int(float(st.xp_n) * float(t[clampi(lv, 0, t.size() - 1)]))
	return roundi(float(st.xp_n) / 1.1 * float(t[clampi(cap, 0, t.size() - 1)]))


func _reward(xp: int, money: int) -> void:
	if xp > 0:
		PlayerData.gain_xp(xp, false)
	if money > 0:
		PlayerData.set_copper(PlayerData.total_copper() + money)
		PlayerData.message.emit("You are awarded %s!" % PlayerData.money_string(money), "system")


## Event monsters (ClassicQuests TrySpawnEvent): a step with a spawn brings its monster(s) when you come within its
## trigger radius of the point (radius 0: wherever you are) - a short way off, coming at you; a peaceful one (an NPC
## summoned to talk) stands at its point. They leave after their despawn time, or when the quest moves on; after one
## dies without the step moving on, it can come again 30 s later.
func _events_tick() -> void:
	var live := {}
	for id in PlayerData.quests.keys():
		var n := int(PlayerData.quests[id].step)
		var sp: Dictionary = step_of(id).get("spawn", {})
		if sp.is_empty():
			continue
		var key := "%s:%d" % [id, n]
		live[key] = true
		var out: Array = _events.get(key, [])
		out = out.filter(func(s): return (s as NpcState).alive)
		_events[key] = out
		if not out.is_empty():
			_event_left[key] = float(_event_left.get(key, 0.0)) - 1.0
			if float(_event_left[key]) <= 0.0:
				for s in out:
					viewer.npcs.remove_spawn(s)
				_events.erase(key)
			continue
		if _cooldowns.has("event:" + key) or viewer.player.dead or int(sp.get("zone", -1)) != int(viewer.zone.info.id):
			continue
		if _events.has(key + ":fought"):
			_events.erase(key + ":fought")
			_cooldowns["event:" + key] = 30.0
			continue
		var at := Vector3(sp.pos[0], sp.pos[1], sp.pos[2])
		var me: Vector3 = viewer.player.global_position
		if float(sp.get("trigger_m", 0)) > 0.0 and Vector2(me.x - at.x, me.z - at.z).length() > float(sp.trigger_m):
			continue
		var made := []
		for i in maxi(1, int(sp.get("count", 1))):
			made.append(_spawn_event(sp, i))
		_events[key] = made
		_events[key + ":fought"] = true
		_event_left[key] = float(sp.get("despawn", 600))
	for key in _events.keys():
		var base := String(key).trim_suffix(":fought")
		if not live.has(base):
			for s in (_events[key] if _events[key] is Array else []):
				viewer.npcs.remove_spawn(s)
			_events.erase(key)


func _spawn_event(sp: Dictionary, i: int) -> NpcState:
	var tpl: Dictionary = sp.get("npc_template", {}) if sp.get("npc_template") is Dictionary else {}
	var model := int(sp.get("model", 0))
	if model <= 0 and tpl.has("model"):
		var ms := String(tpl.model).replace(",", ";").split(";", false)
		model = int(ms[randi() % ms.size()]) if not ms.is_empty() else 0
	var peaceful := bool(sp.get("peaceful", false))
	var me: Vector3 = viewer.player.global_position
	var pos := Vector3(sp.pos[0] + 2.0 * i, sp.pos[1], sp.pos[2])
	if not peaceful:                                       # behind the player, 15-22 m off, then it comes for you
		var a: float = viewer.player.facing() + PI + i * 0.7
		pos = me + Vector3(-sin(a), 0, -cos(a)) * randf_range(15.0, 22.0)
		pos.y = viewer.zone.height_at(pos.x, pos.z, me.y)
	var level := int(sp.get("level", 0)) if int(sp.get("level", 0)) > 0 else int(String(tpl.get("level", "1")).split(";")[0])
	var s := {"id": "event_%s_%d" % [String(sp.name), Time.get_ticks_msec() + i], "name": String(sp.name), "guild": "",
			"level": level, "levels": [level], "realm": 3 if peaceful else 0, "role": null, "model": str(model),
			"size": int(tpl.get("size", 50)) if str(tpl.get("size", "")).is_valid_int() else 50, "gender": 0,
			"pos": [pos.x, pos.y, pos.z], "heading": 0, "aggro_level": 0 if peaceful else 100,
			"aggro_range": 0 if peaceful else 500, "roam": 0, "flags": 0, "speed": 0, "items": "",
			"equipment": String(tpl.get("equipment", "") if tpl.get("equipment") != null else ""), "stats": [],
			"damage_type": int(tpl.get("damage_type", 0) if tpl.get("damage_type") != null else 0), "respawn": 0,
			"defense": [0, 0, 0, 0]}
	var st: NpcState = viewer.npcs.add_spawn(s)
	if not peaceful and viewer.combat:
		viewer.combat._engage(st)
	return st


## A lost step item comes back from the step's issuer (ClassicQuests NeedsItem / Issuer).
func _reissue(id: String, st: Dictionary, n: Npc) -> void:
	var need := String(st.get("needs_item", ""))
	if need == "" or String(st.get("issuer", "")).to_lower() != String(n.spawn.name).to_lower() or PlayerData.find_item(need) >= 0:
		return
	var it := ItemDb.item(need)
	if not it.is_empty() and PlayerData.first_free() >= 0:
		PlayerData.inventory[PlayerData.first_free()] = {"id": need, "count": 1}
		PlayerData.message.emit("%s gives you another %s." % [String(n.spawn.name), String(it.get("name", ""))], "system")
		PlayerData.inventory_changed.emit()


## Items the step before handed over (ClassicQuests Grant): a player on the step without one gets it.
func _grants(id: String, st: Dictionary) -> void:
	var grant: Array = st.get("grant", [])
	for i in grant.size():
		var item_id := String(grant[i])
		var key := "%s:%d:grant%d" % [id, int(PlayerData.quests[id].step), i]
		if item_id == "" or PlayerData.find_item(item_id) >= 0 or _cooldowns.has(key):
			continue
		_cooldowns[key] = 60.0
		PlayerData.give_item(item_id, String(st.get("grant_from", "")))


## On a classic step's point (flat distance; walkthrough places carry no height), or anywhere in its zone.
func _in_place(custom: Dictionary) -> bool:
	if not custom.has("zone"):
		return true
	if int(custom.zone) != int(viewer.zone.info.id):
		return false
	if float(custom.get("radius_m", 0)) <= 0.0:
		return true
	var p: Array = custom.pos
	var me: Vector3 = viewer.player.global_position
	return Vector2(me.x - float(p[0]), me.z - float(p[2])).length() <= float(custom.radius_m)


func _in_area(area: Dictionary) -> bool:
	if int(area.get("zone", -1)) != int(viewer.zone.info.id):
		return false
	var p: Array = area.pos
	var me: Vector3 = viewer.player.global_position
	return Vector2(me.x - float(p[0]), me.z - float(p[2])).length() <= float(area.get("radius_m", 12.5))


func _changed() -> void:
	PlayerData.quests_changed.emit()
	PlayerData.save_character()


## Give up a quest (journal ABANDON): "Quest cleared!" (AbstractQuest.AbortQuest).
func abandon(id: String) -> void:
	if PlayerData.quests.erase(id):
		PlayerData.message.emit("Quest cleared!", "system")
		_changed()
