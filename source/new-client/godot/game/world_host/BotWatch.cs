using Godot;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace MMOEngine;

// Bot diagnostics for finding progression problems later (owner 2026-10-11: "figure out how you are going to get
// hotspot or bot issues logged so I can tell you to check and fix bot progression issues later on"). From the old
// server's lessons: tagged one-line events with everything needed to diagnose them, rate-limited per bot and tag; every
// camp attempt rolled up per camp; problems counted by zone and 8 m cell; a readable digest.
// Files in <world>/botwatch/: events-<source>.jsonl, camps-<source>.json, hotspots-<source>.json,
// progress-<source>.json; the digest is <world>/BOT REPORT.txt (the host writes it, folding in the game's files).
// Never changes what a bot does.
public sealed class BotWatch
{
	readonly string _dir, _source, _reportPath;
	readonly StringBuilder _pending = new();
	readonly Dictionary<string, double> _lastByBotTag = new();
	readonly Dictionary<string, Hot> _hot = new();
	readonly Dictionary<string, CampStat> _camps = new();
	readonly Dictionary<string, int> _tagHour = new();
	readonly Queue<(double t, string tag)> _recent = new();
	readonly Dictionary<int, int> _levelMinutesSum = new(), _levelMinutesN = new();
	double _now, _nextFlush, _nextReport = 60;

	sealed class Hot { public string Zone = ""; public Vector3 Pos; public Dictionary<string, int> Counts = new(); public HashSet<string> Bots = new(); public string Last = ""; }
	sealed class CampStat { public string Zone = ""; public Vector3 Pos; public int Level, Attempts, Kills, Deaths, Timeouts, Abandons; public string LastReason = ""; }

	// Tags that are never rate-limited (each one matters on its own).
	static readonly HashSet<string> Always = new() { "DEATH", "LEVEL", "PROMOTE", "TRAIN", "CAMP_ABANDON", "SELL", "EQUIP", "ARROWS", "ZONE_CROSS" };
	// Tags that count toward the hotspot map.
	static readonly HashSet<string> Spot = new() { "STUCK", "WEDGED", "ROUTE_FAIL", "PULL_TIMEOUT", "DEATH", "STALL", "FALL", "ROUTE_THREAT" };

	public BotWatch(string worldDir, string source)
	{
		_dir = ProjectSettings.GlobalizePath(worldDir + "/botwatch");
		_reportPath = ProjectSettings.GlobalizePath(worldDir + "/BOT REPORT.txt");
		_source = source;
		try { Directory.CreateDirectory(_dir); } catch { }
	}

	public void Tick(double now, IEnumerable<BotAgent> agents)
	{
		_now = now;
		while (_recent.Count > 0 && now - _recent.Peek().t > 3600)
		{
			var (_, tag) = _recent.Dequeue();
			if (_tagHour.TryGetValue(tag, out int n)) _tagHour[tag] = n - 1;
		}
		if (now >= _nextFlush)
		{
			_nextFlush = now + 10;
			FlushEvents();
		}
		if (now >= _nextReport)
		{
			_nextReport = now + 300;
			WriteFiles(agents);
		}
	}

	// One event. detail: the human reason; extra: a few named values (target, distance...).
	public void Event(BotAgent a, string tag, string detail, double rateSeconds = 60, params (string k, object v)[] extra)
	{
		if (a == null) return;
		string key = a.Id + ":" + tag;
		if (!Always.Contains(tag) && _lastByBotTag.TryGetValue(key, out double last) && _now - last < rateSeconds) return;
		_lastByBotTag[key] = _now;
		var p = a.Body != null ? a.Body.Position : Vector3.Zero;
		var d = new Godot.Collections.Dictionary
		{
			["t"] = Time.GetDatetimeStringFromSystem(), ["tag"] = tag, ["bot"] = a.Name, ["id"] = a.Id,
			["class"] = ClassOf(a), ["level"] = a.Level, ["realm"] = a.Realm, ["zone"] = a.Zone?.Data.Name ?? "",
			["zone_id"] = a.Zone?.Data.Id ?? -1, ["pos"] = new Godot.Collections.Array { Mathf.Round(p.X), Mathf.Round(p.Y), Mathf.Round(p.Z) },
			["state"] = a.State.ToString(), ["goal"] = a.Goal_, ["detail"] = detail,
		};
		foreach (var (k, v) in extra) d[k] = Variant.From(v?.ToString() ?? "");
		_pending.Append(Json.Stringify(d)).Append('\n');
		_tagHour[tag] = (_tagHour.TryGetValue(tag, out int c) ? c : 0) + 1;
		_recent.Enqueue((_now, tag));
		if (Spot.Contains(tag) && a.Zone != null)
		{
			string hk = $"{a.Zone.Data.Id}:{(int)(p.X / 8)}:{(int)(p.Z / 8)}";
			if (!_hot.TryGetValue(hk, out var h)) _hot[hk] = h = new Hot { Zone = a.Zone.Data.Name, Pos = p.Round() };
			h.Counts[tag] = (h.Counts.TryGetValue(tag, out int hc) ? hc : 0) + 1;
			if (h.Bots.Count < 12) h.Bots.Add(a.Name);
			h.Last = Time.GetDatetimeStringFromSystem();
		}
		if (tag == "LEVEL" && a.LevelStartT > 0)
		{
			int mins = (int)((_now - a.LevelStartT) / 60);
			_levelMinutesSum[a.Level - 1] = (_levelMinutesSum.TryGetValue(a.Level - 1, out int s) ? s : 0) + mins;
			_levelMinutesN[a.Level - 1] = (_levelMinutesN.TryGetValue(a.Level - 1, out int n) ? n : 0) + 1;
		}
	}

	// A camp attempt's outcome (field: attempt / kill / death / timeout / abandon).
	public void Camp(BotAgent a, int campIdx, string field, string reason = "")
	{
		if (a?.Zone == null || campIdx < 0 || campIdx >= a.Zone.Data.Camps.Length) return;
		string key = $"{a.Zone.Data.Id}:{campIdx}";
		if (!_camps.TryGetValue(key, out var c))
			_camps[key] = c = new CampStat { Zone = a.Zone.Data.Name, Pos = a.Zone.Data.Camps[campIdx].Round(), Level = a.Zone.Data.CampLevels[campIdx] };
		switch (field)
		{
			case "attempt": c.Attempts++; break;
			case "kill": c.Kills++; break;
			case "death": c.Deaths++; break;
			case "timeout": c.Timeouts++; break;
			case "abandon": c.Abandons++; c.LastReason = reason; break;
		}
	}

	static string ClassOf(BotAgent a)
	{
		if (a.Record == null) return "";
		return a.Record.TryGetValue("class_name", out var c) ? (string)c : "";
	}

	void FlushEvents()
	{
		if (_pending.Length == 0) return;
		try
		{
			string path = Path.Combine(_dir, $"events-{_source}.jsonl");
			var fi = new FileInfo(path);
			if (fi.Exists && fi.Length > 20_000_000)
				File.Move(path, path + ".old", true);
			File.AppendAllText(path, _pending.ToString());
			_pending.Clear();
		}
		catch { }                                           // diagnostics never stop a bot
	}

	public void WriteFiles(IEnumerable<BotAgent> agents)
	{
		FlushEvents();
		try
		{
			var hot = new Godot.Collections.Array();
			foreach (var h in _hot.Values.OrderByDescending(h => h.Counts.Values.Sum()).Take(300))
			{
				var counts = new Godot.Collections.Dictionary();
				foreach (var kv in h.Counts) counts[kv.Key] = kv.Value;
				hot.Add(new Godot.Collections.Dictionary { ["zone"] = h.Zone, ["pos"] = h.Pos.ToString(), ["counts"] = counts,
					["bots"] = new Godot.Collections.Array(h.Bots.Select(n => Variant.From(n))), ["last"] = h.Last });
			}
			File.WriteAllText(Path.Combine(_dir, $"hotspots-{_source}.json"), Json.Stringify(hot, "\t"));
			var camps = new Godot.Collections.Array();
			foreach (var kv in _camps.OrderByDescending(kv => kv.Value.Deaths + kv.Value.Timeouts + kv.Value.Abandons))
				camps.Add(new Godot.Collections.Dictionary { ["camp"] = kv.Key, ["zone"] = kv.Value.Zone, ["pos"] = kv.Value.Pos.ToString(),
					["level"] = kv.Value.Level, ["attempts"] = kv.Value.Attempts, ["kills"] = kv.Value.Kills, ["deaths"] = kv.Value.Deaths,
					["pull_timeouts"] = kv.Value.Timeouts, ["abandons"] = kv.Value.Abandons, ["last_abandon"] = kv.Value.LastReason });
			File.WriteAllText(Path.Combine(_dir, $"camps-{_source}.json"), Json.Stringify(camps, "\t"));
			var prog = new Godot.Collections.Array();
			foreach (var a in agents.Where(a => !a.Companion))
				prog.Add(new Godot.Collections.Dictionary { ["bot"] = a.Name, ["class"] = ClassOf(a), ["level"] = a.Level, ["zone"] = a.Zone?.Data.Name ?? "",
					["state"] = a.State.ToString(), ["kills"] = a.Kills, ["deaths"] = a.Deaths,
					["min_at_level"] = (int)((_now - a.LevelStartT) / 60), ["min_since_xp"] = (int)((_now - a.LastXpT) / 60) });
			File.WriteAllText(Path.Combine(_dir, $"progress-{_source}.json"), Json.Stringify(prog, "\t"));
			if (_source == "host") WriteReport(agents);
		}
		catch { }
	}

	void WriteReport(IEnumerable<BotAgent> agentsIn)
	{
		var agents = agentsIn.Where(a => !a.Companion).ToList();
		var sb = new StringBuilder();
		sb.AppendLine($"BOT REPORT - {Time.GetDatetimeStringFromSystem()} - {agents.Count} gamebots on the world host");
		sb.AppendLine("(botwatch\\ folder: events-*.jsonl for every event, camps/hotspots/progress-*.json)");
		sb.AppendLine();
		sb.AppendLine("EVENTS IN THE LAST HOUR");
		foreach (var kv in _tagHour.Where(kv => kv.Value > 0).OrderByDescending(kv => kv.Value))
			sb.AppendLine($"  {kv.Key,-14} {kv.Value}");
		sb.AppendLine();
		sb.AppendLine("LEVELS (bots at each level; average minutes the level took)");
		foreach (var g in agents.GroupBy(a => a.Level).OrderBy(g => g.Key))
		{
			string took = _levelMinutesN.TryGetValue(g.Key, out int n) && n > 0 ? $"{_levelMinutesSum[g.Key] / n} min ({n} done)" : "-";
			sb.AppendLine($"  level {g.Key,2}: {g.Count(),5} bots   took {took}");
		}
		sb.AppendLine();
		sb.AppendLine("STALLED (alive, no experience for 30+ minutes)");
		foreach (var a in agents.Where(a => a.Alive && _now - a.LastXpT > 1800).OrderByDescending(a => _now - a.LastXpT).Take(40))
			sb.AppendLine($"  {a.Name} (level {a.Level} {ClassOf(a)}) in {a.Zone?.Data.Name}: {(int)((_now - a.LastXpT) / 60)} min, {a.State} {a.Goal_} - {(a.Log.Count > 0 ? a.Log[^1].Trim() : "")}");
		sb.AppendLine();
		sb.AppendLine("HOTSPOTS (zone, spot: counts)");
		foreach (var h in _hot.Values.OrderByDescending(h => h.Counts.Values.Sum()).Take(25))
			sb.AppendLine($"  {h.Zone} {h.Pos}: {string.Join(", ", h.Counts.Select(kv => $"{kv.Key} {kv.Value}"))} ({h.Bots.Count} bots)");
		sb.AppendLine();
		sb.AppendLine("WORST CAMPS (deaths, pull timeouts, abandons per attempt)");
		foreach (var c in _camps.Values.Where(c => c.Attempts > 0).OrderByDescending(c => (c.Deaths * 3 + c.Timeouts + c.Abandons * 2) / (float)c.Attempts).Take(20))
			sb.AppendLine($"  {c.Zone} {c.Pos} (level {c.Level}): {c.Attempts} attempts, {c.Kills} kills, {c.Deaths} deaths, {c.Timeouts} timeouts, {c.Abandons} abandons {c.LastReason}");
		// the game's own files (bots near the player), when it has written any
		string game = Path.Combine(_dir, "hotspots-game.json");
		if (File.Exists(game)) sb.AppendLine().AppendLine("(bots near the player: see hotspots-game.json / camps-game.json / events-game.jsonl)");
		File.WriteAllText(_reportPath, sb.ToString());
	}
}
