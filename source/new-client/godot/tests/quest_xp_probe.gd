extends SceneTree
## Debug (owner 2026-10-10: period quest experience): what chosen quests pay at several levels, against the period
## figures quoted in pipeline/build_quest_xp.py.
##   --headless --path godot -s res://tests/quest_xp_probe.gd


const CASES := [
	["Gazsi's Nightmares", [39, 41, 49], "170,700,780 / 225,241,032 / 356,515,840"],
	["Twisted Evil", [38, 39], "148,603,664 / 170,700,780"],
	["Missing Tapestry", [33, 34], "39,963,964 / 50,351,451"],
	["Face the Twisted", [42, 44], "152,196,473 / 182,567,690"],
	["Spirits of the Orchard", [36, 44], "~99,000,000 / 207,540,645"],
	["Rhoiwyn's Necklace", [49, 50], "~2,900,000,000 / 3,321,888,768"],
	["Morvalt Streber Scalps -- Kill Task", [31, 34], "1,651,404 / 1,651,404"],
	["Sad Fomorie", [10, 12, 15], "(improvised before: 327,600)"],
	["In the Interest of Plants", [7, 9], "(improvised before: 3,300)"],
	["Strange Bedfellows", [45, 47], "(improvised before: 873,600,000)"],
	["Cristin's Supplies", [8, 10], "2,560 at 8 and at 10"],
]


func _initialize() -> void:
	await process_frame
	var qe: Script = load("res://game/quests/quest_engine.gd")      # loaded after the autoloads exist
	var by_name := {}
	for id in QuestDb.all():
		var q: Dictionary = QuestDb.all()[id]
		if not by_name.has(String(q.name)):
			by_name[String(q.name)] = q
	for c in CASES:
		var q: Dictionary = by_name.get(String(c[0]), {})
		if q.is_empty():
			print("[qxp] missing ", c[0])
			continue
		var line := "[qxp] %s (min %d):" % [c[0], int(q.min)]
		for lv in c[1]:
			root.get_node("PlayerData").level = int(lv)
			var total := 0
			for st in q.steps:
				total += int(qe.call("step_xp", st))
			line += "  L%d %s" % [lv, _n(total)]
		print(line, "   period: ", c[2])
	quit()


func _n(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
