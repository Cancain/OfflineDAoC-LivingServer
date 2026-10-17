class_name SkillInfo
extends RefCounted
## The information (delve) text of a spell, style or ability - right-click in the magic / combat pages or on a
## quickbar slot (owner 2026-10-10). Lines and labels as the old server's DelveInfo (language/EN/Spells.txt:
## "Function:", "Target:", "Range:", "Casting time:", "Power cost:", "Damage:", "Damage Type:", "Duration:",
## "Frequency:", "Radius:", "Recast time:"), from the spell / style rows the game already uses.

const DAMAGE_TYPES := {1: "Crush", 2: "Slash", 3: "Thrust", 10: "Body", 11: "Cold", 12: "Energy", 13: "Heat",
		14: "Matter", 15: "Spirit", 22: "Natural"}
const OPENINGS := {0: "Offensive", 1: "Defensive", 2: "Positional"}
const RESULTS := {1: "Any", 2: "Miss", 3: "Hit", 4: "Parry", 5: "Block", 6: "Evade", 7: "Fumble", 8: "Style"}
const POSITIONS := {0: "Back", 1: "Side", 2: "Front"}


static func lines(entry: Dictionary) -> Array:
	match String(entry.get("kind", "")):
		"spell":
			return spell(ClassDb.spell(int(entry.get("id", 0))))
		"style":
			return style(ClassDb.style(int(entry.get("id", 0))))
		_:
			var a := ClassDb.ability(String(entry.get("id", "")))
			return [String(a.get("description", "")) if String(a.get("description", "")) != "" else "No information."]


static func _secs(s: float) -> String:
	if s <= 0.0:
		return "Instant"
	if s >= 60.0:
		return "%d:%02d min" % [int(s) / 60, int(s) % 60]
	return ("%.1f sec" % s).replace(".0 sec", " sec")


static func spell(sp: Dictionary) -> Array:
	if sp.is_empty():
		return ["No information."]
	var out := []
	if String(sp.get("description", "")) != "":
		out.append(String(sp.description))
		out.append("")
	out.append("Function: %s" % String(sp.get("type", "")).capitalize().to_lower())
	out.append("Target: %s" % String(sp.get("target", "")))
	if int(sp.get("range", 0)) > 0:
		out.append("Range: %d" % int(sp.range))
	if int(sp.get("radius", 0)) > 0:
		out.append("Radius: %d" % int(sp.radius))
	if int(sp.get("duration", 0)) > 0:
		out.append("Duration: " + _secs(float(sp.duration)))
	if int(sp.get("frequency", 0)) > 0:
		out.append("Frequency: " + _secs(float(sp.frequency) / 10.0))
	if float(sp.get("damage", 0)) != 0.0:
		out.append("Damage: %s" % str(float(sp.damage)).trim_suffix(".0"))
	if int(sp.get("damagetype", 0)) > 0 and float(sp.get("damage", 0)) != 0.0:
		out.append("Damage Type: %s" % DAMAGE_TYPES.get(int(sp.damagetype), str(int(sp.damagetype))))
	if float(sp.get("value", 0)) != 0.0:
		out.append("Value: %s" % str(float(sp.value)).trim_suffix(".0"))
	if int(sp.get("power", 0)) != 0:
		out.append("Power cost: %d%s" % [absi(int(sp.power)), "%" if int(sp.power) < 0 else ""])
	if int(sp.get("concentration", 0)) > 0:
		out.append("Concentration cost: %d" % int(sp.concentration))
	out.append("Casting time: " + _secs(float(sp.get("casttime", 0))))
	if int(sp.get("recastdelay", 0)) > 0:
		out.append("Recast time: " + _secs(float(sp.recastdelay)))
	return out


static func style(st: Dictionary) -> Array:
	if st.is_empty():
		return ["No information."]
	var out := []
	var ot := int(st.get("openingrequirementtype", 0))
	var ov := int(st.get("openingrequirementvalue", 0))
	var ar := int(st.get("attackresultrequirement", 0))
	match ot:
		0:
			out.append("Opening: " + ("any attack" if ov == 0 else "after your style"))
		1:
			out.append("Opening: your enemy's %s" % RESULTS.get(ar, "attack").to_lower())
		2:
			out.append("Opening: %s of your target" % POSITIONS.get(ov, "Behind").to_lower())
	out.append("Specialization: %s %d" % [String(ClassDb.spec(String(st.get("speckeyname", ""))).get("name", st.get("speckeyname", ""))),
			int(st.get("speclevelrequirement", 0))])
	out.append("Fatigue cost: %d" % int(st.get("endurancecost", 0)))
	if int(st.get("bonustohit", 0)) != 0:
		out.append("Bonus to hit: %d" % int(st.bonustohit))
	if int(st.get("bonustodefense", 0)) != 0:
		out.append("Bonus to defense: %d" % int(st.bonustodefense))
	if float(st.get("growthrate", 0)) > 0.0:
		out.append("Damage growth: %s" % str(snappedf(float(st.growthrate), 0.001)))
	if int(st.get("stealthrequirement", 0)) != 0:
		out.append("Requires stealth")
	return out
