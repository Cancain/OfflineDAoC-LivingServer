// The permanent bot roster (bot plan phase 3): every gamebot is a character dictionary in the same format as a
// player's (CharacterFactory makes it), plus a "bot" entry: {id, created, goal, state}. Saved as one JSON file in the
// game's user folder (RealmSettings.BOTS_PATH), shared by the game and the world host. The Bot Roster tab's live list
// is a small summary of it (RealmSettings.BOT_ROSTER_PATH).
using Godot;
using System.Collections.Generic;
using System.Linq;

namespace MMOEngine;

public sealed class BotStore
{
	public static readonly string[] Realms = { "alb", "mid", "hib" };   // the realm split's order

	readonly List<Godot.Collections.Dictionary> _bots = new();
	readonly string _path;
	readonly string _rosterPath;
	int _nextId = 1;
	public bool Dirty;

	public BotStore(string path, string rosterPath)
	{
		_path = path;
		_rosterPath = rosterPath;
	}

	public IReadOnlyList<Godot.Collections.Dictionary> Bots => _bots;

	public int Count(string realm) => _bots.Count(b => (string)b["realm"] == realm);

	public static Godot.Collections.Dictionary Info(Godot.Collections.Dictionary bot) =>
		bot.TryGetValue("bot", out var v) ? v.AsGodotDictionary() : new Godot.Collections.Dictionary();

	public void Load()
	{
		_bots.Clear();
		if (FileAccess.FileExists(_path))
		{
			var parsed = Json.ParseString(FileAccess.GetFileAsString(_path));
			if (parsed.VariantType == Variant.Type.Array)
				foreach (var v in parsed.AsGodotArray())
					if (v.VariantType == Variant.Type.Dictionary)
						_bots.Add(v.AsGodotDictionary());
		}
		_nextId = 1 + _bots.Select(b => Info(b).TryGetValue("id", out var id) ? id.AsInt32() : 0).DefaultIfEmpty(0).Max();
	}

	public void Save()
	{
		DirAccess.MakeDirRecursiveAbsolute(_path.GetBaseDir());
		var arr = new Godot.Collections.Array();
		foreach (var b in _bots) arr.Add(b);
		WriteAtomic(_path, Json.Stringify(arr));
		Dirty = false;
	}

	// The Bot Roster tab's list: name, realm, class, level, spec, zone, goal, state.
	public void SaveRoster(System.Func<Godot.Collections.Dictionary, string> zoneName)
	{
		var arr = new Godot.Collections.Array();
		foreach (var b in _bots)
		{
			var info = Info(b);
			arr.Add(new Godot.Collections.Dictionary
			{
				["name"] = b["name"], ["realm"] = b["realm"], ["class"] = b["class_name"],
				["level"] = b.TryGetValue("level", out var l) ? l : 1,
				["spec"] = info.TryGetValue("spec", out var sp) ? sp : "",
				["zone"] = zoneName(b),
				["goal"] = info.TryGetValue("goal", out var g) ? g : "", ["state"] = info.TryGetValue("state", out var st) ? st : "",
			});
		}
		DirAccess.MakeDirRecursiveAbsolute(_rosterPath.GetBaseDir());
		WriteAtomic(_rosterPath, Json.Stringify(arr));
	}

	public void Add(Godot.Collections.Dictionary character)
	{
		character["bot"] = new Godot.Collections.Dictionary
		{
			["id"] = _nextId++, ["created"] = Time.GetUnixTimeFromSystem(), ["goal"] = "", ["state"] = "new",
		};
		_bots.Add(character);
		Dirty = true;
	}

	// Lowering the total retires the newest bots of that realm first.
	public Godot.Collections.Dictionary RetireNewest(string realm)
	{
		var newest = _bots.Where(b => (string)b["realm"] == realm)
			.OrderByDescending(b => Info(b).TryGetValue("id", out var id) ? id.AsInt32() : 0).FirstOrDefault();
		if (newest != null)
		{
			_bots.Remove(newest);
			Dirty = true;
		}
		return newest;
	}

	public Godot.Collections.Dictionary ById(int id)
	{
		foreach (var b in _bots)
			if (Info(b).TryGetValue("id", out var v) && v.AsInt32() == id) return b;
		return null;
	}

	// The game's copy of a bot came back (zone handover): its changed state goes into the saved record.
	public void Apply(Godot.Collections.Dictionary incoming)
	{
		var info = Info(incoming);
		if (!info.TryGetValue("id", out var idv)) return;
		var rec = ById(idv.AsInt32());
		if (rec == null) return;
		foreach (var k in incoming.Keys) rec[k] = incoming[k];
		Dirty = true;
	}

	public HashSet<string> Names() => _bots.Select(b => ((string)b["name"]).ToLowerInvariant()).ToHashSet();

	// Written to a temporary file first, then moved over the old one, so a reader never sees half a file.
	static void WriteAtomic(string path, string text)
	{
		string tmp = path + ".tmp";
		using (var f = FileAccess.Open(tmp, FileAccess.ModeFlags.Write))
		{
			if (f == null) return;
			f.StoreString(text);
		}
		DirAccess.RenameAbsolute(tmp, path);
	}
}
