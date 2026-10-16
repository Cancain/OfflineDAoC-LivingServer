// Your companions in the game (they run here, led by you) and their figures. The world's gamebots, monsters and NPCs
// come from the Offline DAoC server the launcher runs (Offline DAoC Rebuilt, owner 2026-10-11).
using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace MMOEngine;

public partial class GameBots : Node
{
	const double UpdateEvery = 5.0;
	const double ReconnectEvery = 3.0;

	readonly BotSim _sim = new();
	ZoneWorld _zone;
	Node3D _zoneRoot;
	int _zoneId = -1;
	bool _entered;
	// a gamebot as the host streams it: its view, its record (look, gear, name), the last two snapshots' spots
	sealed class Puppet
	{
		public Node3D View;
		public Godot.Collections.Dictionary Record;
		// its last snapshots on the host's clock (seconds): (time, spot, facing) - drawn on that timeline, Delay behind
		public readonly List<(double t, Vector3 p, float f)> Samples = new();
		public string State = "", Realm = "";
		public bool Drawn;
		public float Hp = 1f;
		public int Level = 1;
	}
	readonly Dictionary<int, Puppet> _bots = new();
	// Drawn this far behind the host's newest snapshot, gliding between the two around that moment (the usual client
	// interpolation): a late snapshot no longer stops a bot and then jumps it (owner 2026-10-11: rubberbanding).
	const double Delay = 0.2;
	const double Extrapolate = 0.35;             // no newer snapshot: it carries on at its last speed this long at most
	double _clockOffset = double.NaN;            // local clock - host clock (the smallest seen: the least delayed)
	GDScript _viewScript;
	string _navDir;
	public int TargetId = -1;
	readonly List<(Node3D door, Vector3 at)> _doors = new();   // the zone's door leaves (ZoneLoader.doors)
	double _doorLeft;
	// phase 6: your companions - they run on the same simulation, led by you (never handed to the world host)
	readonly Dictionary<int, (BotAgent agent, Node3D view)> _companions = new();

	public override void _Ready()
	{
		_viewScript = GD.Load<GDScript>("res://game/world_host/bot_view.gd");
		_navDir = (string)GD.Load<GDScript>("res://game/realm_settings.gd").Get("WORLD_DIR") + "/nav";
		foreach (var a in OS.GetCmdlineUserArgs())                 // tests: a test host's folder
			if (a.StartsWith("--world-dir=")) _navDir = a.Substring("--world-dir=".Length) + "/nav";
		_sim.StuckAt = (a, p) => GD.Print($"[bots] stuck: {a.Name} at {p.Round()}");
		_sim.Released = OnReleased;
		_sim.FellAt = (a, m) => GD.Print($"[bots] {a.Name}: {m}");
		_sim.Watch = new BotWatch((string)GD.Load<GDScript>("res://game/realm_settings.gd").Get("WORLD_DIR"), "game");
	}

	// ---------------------------------------------------------------- zones (ZoneViewer -> WorldLink)

	public void ZoneEntered(Node3D zoneRoot, int zoneId)
	{
		if (_zoneId >= 0) ZoneLeft();
		if (!ZoneData.Exists(zoneId)) return;
		_zoneRoot = zoneRoot;
		_zoneId = zoneId;
		_zone = ZoneWorld.ForGame(zoneRoot, ZoneData.Load(zoneId));
		_zone.Combat = GetTree().CurrentScene?.Get("combat").AsGodotObject();   // the game's Combat: your fights and theirs
		_zone.StartNav(_navDir);
		_entered = false;
		_doors.Clear();
		foreach (var d in zoneRoot.Get("doors").AsGodotArray())
			if (d.AsGodotObject() is Node3D dn) _doors.Add((dn, DoorwayOf(dn)));
		SendEnter();
	}

	// Seamless zones: you crossed into another zone of the region (the scene has already moved so the new zone is at the
	// origin). The old zone's bots go back to the host and the new zone's come, as with a loading screen; your
	// companions stay - their bodies move over into the new zone's world where they stand.
	public void SwitchZone(Node3D zoneRoot, int zoneId)
	{
		var keep = new Dictionary<int, (BotAgent agent, Node3D view)>(_companions);
		_companions.Clear();                                       // (ZoneLeft leaves them alone)
		ZoneLeft();
		if (!ZoneData.Exists(zoneId))
		{
			foreach (var (agent, view) in keep.Values)
			{
				_sim.Remove(agent);
				if (IsInstanceValid(view)) view.QueueFree();
			}
			return;
		}
		_zoneRoot = zoneRoot;
		_zoneId = zoneId;
		_zone = ZoneWorld.ForGame(zoneRoot, ZoneData.Load(zoneId));
		_zone.Combat = GetTree().CurrentScene?.Get("combat").AsGodotObject();
		_zone.StartNav(_navDir);
		_entered = false;
		_doors.Clear();
		foreach (var d in zoneRoot.Get("doors").AsGodotArray())
			if (d.AsGodotObject() is Node3D dn) _doors.Add((dn, DoorwayOf(dn)));
		foreach (var kv in keep)
		{
			_sim.Rehome(kv.Value.agent, _zone);
			if (IsInstanceValid(kv.Value.view))
			{
				var g = kv.Value.view.GlobalTransform;
				kv.Value.view.GetParent()?.RemoveChild(kv.Value.view);
				zoneRoot.AddChild(kv.Value.view);
				kv.Value.view.GlobalTransform = g;
			}
			_companions[kv.Key] = kv.Value;
		}
		SendEnter();
	}

	public void ZoneLeft()
	{
		if (_zoneId < 0) return;
		foreach (var p in _bots.Values)
			if (IsInstanceValid(p.View)) p.View.QueueFree();
		_bots.Clear();
		foreach (var (agent, view) in _companions.Values)
		{
			_sim.Remove(agent);                                    // (its sheet's numbers go into its record first)
			if (IsInstanceValid(view)) view.QueueFree();
		}
		_companions.Clear();
		_zone?.FreeNav();
		_zoneId = -1;
		_zone = null;
		_zoneRoot = null;
		TargetId = -1;
	}

	// The middle of a door's doorway (ZoneDoor.center - the closed leaf's middle), else its hinge.
	static Vector3 DoorwayOf(Node3D door)
	{
		var c = door.Call("doorway").AsVector3();
		return float.IsInfinity(c.X) ? door.GlobalPosition : c;
	}

	void SendEnter() { }                         // (no world host: the server's world comes over the client link)

	// ---------------------------------------------------------------- the line to the host

	public override void _Process(double delta) => StepPuppets(delta);

	double _posLeft;

	// A snapshot: each bot's new spot and facing (it moves there over the next snapshot interval), what it shows,
	// its weapons, its health, and the moments since the last one.
	void Snapshot(Godot.Collections.Dictionary m)
	{
		double ts = m.TryGetValue("ts", out var tv) ? tv.AsDouble() : Time.GetTicksUsec() / 1e6;
		double off = Time.GetTicksUsec() / 1e6 - ts;
		// the clocks' offset: the smallest seen is the least delayed arrival; it drifts up slowly (a sleeping host)
		_clockOffset = double.IsNaN(_clockOffset) || off < _clockOffset ? off : _clockOffset + 0.002;
		foreach (var rv in m["bots"].AsGodotArray())
		{
			var row = rv.AsGodotArray();
			if (!_bots.TryGetValue(row[0].AsInt32(), out var p) || !IsInstanceValid(p.View)) continue;
			var to = new Vector3(row[1].AsSingle(), row[2].AsSingle(), row[3].AsSingle());
			if (p.Samples.Count > 0 && p.Samples[^1].p.DistanceSquaredTo(to) > 64f) p.Samples.Clear();   // placed: no slide
			p.Samples.Add((ts, to, row[4].AsSingle()));
			if (p.Samples.Count > 8) p.Samples.RemoveAt(0);
			string state = (string)row[5];
			if (state != p.State) { p.State = state; p.View.Call("set_state", state); }
			bool drawn = row[6].AsBool();
			if (drawn != p.Drawn) { p.Drawn = drawn; p.View.Call("set_drawn", drawn); }
			p.Hp = row[7].AsSingle();
		}
		foreach (var ev in m["ev"].AsGodotArray())
		{
			var e = ev.AsGodotArray();
			if (_bots.TryGetValue(e[0].AsInt32(), out var p) && IsInstanceValid(p.View)) Moment(p.View, (string)e[1]);
		}
	}

	// A one-shot on a bot's figure: a swing, a flinch, a defence, the bow, a spell's moments.
	static void Moment(Node3D view, string what)
	{
		int c = what.IndexOf(':');
		if (c > 0 && int.TryParse(what.AsSpan(c + 1), out int fx))
		{
			view.Call(what[..c] switch { "cast" => "cast_begin", "fire" => "cast_fire", "land" => "cast_land", _ => "cast_fizzle" }, fx);
			return;
		}
		switch (what)
		{
			case "swing": view.Call("swing"); break;
			case "flinch": view.Call("flinch"); break;
			case "draw": view.Call("bow", "draw"); break;
			case "shoot": view.Call("bow", "shoot"); break;
			default: view.Call("defend", what); break;
		}
	}

	// Every frame: each bot moved along from its last spot toward the new one (only on change - a transform set
	// pushes new transforms to its ~30 parts), and a closed door it is standing in opens as for a player's click.
	void StepPuppets(double delta)
	{
		double show = Time.GetTicksUsec() / 1e6 - (double.IsNaN(_clockOffset) ? 0 : _clockOffset) - Delay;   // host time drawn
		foreach (var p in _bots.Values)
		{
			if (!IsInstanceValid(p.View) || p.Samples.Count == 0) continue;
			var s = p.Samples;
			Vector3 at;
			float face;
			int i = s.Count - 1;
			while (i > 0 && s[i - 1].t > show) i--;                 // s[i] is the first sample after the moment drawn
			if (show >= s[^1].t)
			{
				// past the newest: carry on at its last speed for a moment (a late snapshot), then hold
				var last = s[^1];
				at = last.p;
				if (s.Count > 1)
				{
					var prev = s[^2];
					double span = Math.Max(1e-3, last.t - prev.t);
					double ahead = Math.Min(show - last.t, Extrapolate);
					at = last.p + (last.p - prev.p) * (float)(ahead / span);
				}
				face = last.f;
			}
			else if (i == 0)
			{
				at = s[0].p;
				face = s[0].f;
			}
			else
			{
				var a = s[i - 1];
				var b = s[i];
				float k = (float)Math.Clamp((show - a.t) / Math.Max(1e-3, b.t - a.t), 0.0, 1.0);
				at = a.p.Lerp(b.p, k);
				face = Mathf.RadToDeg(Mathf.LerpAngle(Mathf.DegToRad(a.f), Mathf.DegToRad(b.f), k));
			}
			if (p.View.GlobalPosition != at) p.View.GlobalPosition = at;
			var rot = new Vector3(0, Mathf.DegToRad(face) + Mathf.Pi, 0);   // the figures face +Z (Player)
			if (p.View.Rotation != rot) p.View.Rotation = rot;
		}
		_puppetDoorLeft -= delta;
		if (_puppetDoorLeft > 0 || _doors.Count == 0) return;
		_puppetDoorLeft = 0.25;
		foreach (var p in _bots.Values)
		{
			if (!IsInstanceValid(p.View) || p.State == "dead") continue;
			var at = p.View.GlobalPosition;
			foreach (var (door, dat) in _doors)
			{
				if (at.DistanceSquaredTo(dat) > 6.25f || Math.Abs(at.Y - dat.Y) > 2.5f || !IsInstanceValid(door)) continue;
				if (!door.Get("is_open").AsBool()) door.Call("open_door");
				else door.Call("hold_open");
			}
		}
	}

	double _puppetDoorLeft;

	// A gamebot comes into view (the host streams it): its figure where the host has it.
	void AddBot(Godot.Collections.Dictionary rec)
	{
		if (_zone == null || _zoneRoot == null) return;
		int id = BotStore.Info(rec)["id"].AsInt32();
		if (_bots.ContainsKey(id)) return;
		var loc = rec["location"].AsGodotDictionary();
		var pa = loc["pos"].AsGodotArray();
		var pos = new Vector3(pa[0].AsSingle(), pa[1].AsSingle(), pa[2].AsSingle());
		float face = loc.TryGetValue("face", out var f) ? f.AsSingle() : 0f;
		var view = _viewScript.New().As<Node3D>();
		_zoneRoot.AddChild(view);
		view.Call("setup", rec);
		view.GlobalPosition = pos;
		_bots[id] = new Puppet
		{
			View = view, Record = rec,
			Realm = rec.TryGetValue("realm", out var rl) ? (string)rl : "", Level = rec.TryGetValue("level", out var lv) ? lv.AsInt32() : 1,
		};
	}

	// ---------------------------------------------------------------- simulation + views

	// Perf's live log: this game's bots' share of the physics tick (and BotSim's parts)
	public double PhysUs;
	public int PhysTicks;

	public string PhysReport()
	{
		int n = Math.Max(PhysTicks, 1);
		var parts = string.Join(", ", _sim.Prof.Where(kv => !kv.Key.EndsWith(" n") && !kv.Key.EndsWith("calls"))
			.OrderByDescending(kv => kv.Value).Take(5).Select(kv => $"{kv.Key} {kv.Value / 1000.0 / n:0.00}"));
		string r = $"bots {PhysUs / 1000.0 / n:0.00} ms ({parts})";
		_sim.Prof.Clear();
		PhysUs = 0;
		PhysTicks = 0;
		return r;
	}

	public override void _PhysicsProcess(double delta)
	{
		ulong pt0 = Time.GetTicksUsec();
		PhysicsStep(delta);
		PhysUs += Time.GetTicksUsec() - pt0;
		PhysTicks++;
	}

	void PhysicsStep(double delta)
	{
		if (_zone == null) return;
		LeaderInfo();
		_sim.Tick(delta);
		// a closed door in a bot's way opens as for a player's click (ZoneDoor.open_door; it closes after 5 s) - the
		// host's world has no door leaves, so its paths go through doorways
		_doorLeft -= delta;
		if (_doorLeft <= 0 && _doors.Count > 0)
		{
			// any living bot or companion at a doorway opens a closed door (as a player's click would) and keeps an open
			// one open while it is still in the doorway - only travelling bots opened them, measured from the hinge, and
			// the leaf swung shut on bots standing in the doorway (owner 2026-10-11: bots crowding a hut door in Connla)
			_doorLeft = 0.25;
			foreach (var (agent, _) in _companions.Values)
			{
				if (agent.Body == null || agent.State == BotSim.St.Dead || agent.State == BotSim.St.Riding) continue;
				var p = agent.Body.GlobalPosition;
				foreach (var (door, at) in _doors)
				{
					if (p.DistanceSquaredTo(at) > 6.25f || Math.Abs(p.Y - at.Y) > 2.5f || !IsInstanceValid(door)) continue;
					if (!door.Get("is_open").AsBool()) door.Call("open_door");
					else door.Call("hold_open");
				}
			}
		}
		foreach (var (agent, view) in _companions.Values)
		{
			if (agent.Body == null || !IsInstanceValid(view)) continue;
			if (agent.State != BotSim.St.Riding)                  // (riders: PlaceCompanionRider)
			{
				// only on change: a transform set (even to the same value) pushes new transforms to every child - ~30
				// mesh parts, the skeleton, the labels, the click shape (the NPCs' lesson, crowd_probe)
				var at = agent.Body.GlobalPosition;
				if (view.GlobalPosition != at) view.GlobalPosition = at;
				var rot = new Vector3(0, Mathf.DegToRad(agent.Face) + Mathf.Pi, 0);   // the figures face +Z (Player)
				if (view.Rotation != rot) view.Rotation = rot;
			}
			string shown = BotSim.ShownStateOf(agent);
			bool drawn = BotSim.ShownDrawnOf(agent);
			if (drawn != agent.ShownDrawn)                         // weapons out for a fight, sheathed after (BotView)
			{
				agent.ShownDrawn = drawn;
				view.Call("set_drawn", drawn);
			}
			if (shown != agent.ShownState)                        // the figure's state only when it changes
			{
				agent.ShownState = shown;
				view.Call("set_state", shown);
			}
			foreach (var ca in agent.CastAnims) Moment(view, ca);
			agent.CastAnims.Clear();
			if (agent.Anim != "")
			{
				Moment(view, agent.Anim);
				agent.Anim = "";
			}
		}
	}

	// A bot released its corpse: to its bind spot (or start) - here if that's in this zone, else the world host takes it
	// (its record without a location: the host puts it at its start, or the bind spot set in "location").
	void OnReleased(BotAgent a, Godot.Collections.Dictionary bind)
	{
		if (bind.Count > 0 && bind["zone"].AsInt32() == _zoneId)
		{
			var pa = bind["pos"].AsGodotArray();
			_sim.Place(a, new Vector3(pa[0].AsSingle(), pa[1].AsSingle(), pa[2].AsSingle()), bind.TryGetValue("face", out var f) ? f.AsSingle() : 0f);
			return;
		}
		if (bind.Count == 0 && _zone != null && StartIn(a.Record, _zone.Data, out var sp, out var sf))
		{
			_sim.Place(a, sp, sf);
			return;
		}
		// (another zone: only gamebots ever were - they run on the host now)
	}

	// Its start spot (the old server's StartupLocation) when that is in this zone.
	public static bool StartIn(Godot.Collections.Dictionary rec, ZoneData z, out Vector3 pos, out float face)
	{
		pos = Vector3.Zero;
		face = 0f;
		if (!rec.TryGetValue("start", out var sv) || sv.VariantType != Variant.Type.Dictionary) return false;
		var st = sv.AsGodotDictionary();
		if (!st.ContainsKey("x") || st["zone"].AsInt32() != z.Id) return false;
		float sx = st["x"].AsSingle() * 0.025f, sz = st["y"].AsSingle() * 0.025f;
		pos = new Vector3(sx, Math.Max(z.Grid(sx, sz), st["z"].AsSingle() * 0.025f), sz);   // as zone_viewer places a new character
		face = st.TryGetValue("heading", out var h) ? -h.AsSingle() * 360f / 4096f : 0f;
		return true;
	}

	// ---------------------------------------------------------------- your companions (Companions.gd)

	// The leader's state for the companions' brain: where you are and face, sitting, dead; the game's Combat.
	void LeaderInfo()
	{
		var scene = GetTree().CurrentScene;
		if (scene == null || _companions.Count == 0) return;
		if (scene.Get("player").AsGodotObject() is Node3D p)
		{
			_sim.LeaderPos = p.GlobalPosition;
			_sim.LeaderFace = Mathf.RadToDeg(p.Call("facing").AsSingle());
			_sim.LeaderSitting = p.Get("sitting").AsBool();
			_sim.LeaderDead = p.Get("dead").AsBool();
		}
		_sim.Combat = scene.Get("combat").AsGodotObject();
	}

	// A companion joins you in this zone (hired, summoned, revived, or arriving with you): its body, its figure with
	// its gear and an orange (grouped) nameplate. Returns its BotFoe (its live character sheet).
	public GodotObject AddCompanion(Godot.Collections.Dictionary rec, Vector3 pos, float face)
	{
		if (_zone == null || _zoneRoot == null) return null;
		int id = rec["companion"].AsGodotDictionary()["id"].AsInt32();
		if (_companions.TryGetValue(id, out var c)) return c.agent.Foe;
		var agent = _sim.Add(rec, _zone, pos, face, id);
		agent.Slot = _companions.Count;
		agent.State = BotSim.St.Follow;
		var view = _viewScript.New().As<Node3D>();
		_zoneRoot.AddChild(view);
		view.Call("setup", rec);
		view.Set("bot_id", id);
		view.Set("companion", true);
		view.Set("grouped", true);
		view.GlobalPosition = pos;
		_companions[id] = (agent, view);
		return agent.Foe;
	}

	public void RemoveCompanion(int id)
	{
		if (!_companions.Remove(id, out var c)) return;
		_sim.Remove(c.agent);
		if (IsInstanceValid(c.view)) c.view.QueueFree();
		int slot = 0;                                             // the rest close up the formation
		foreach (var (agent, _) in _companions.Values.OrderBy(v => v.agent.Slot)) agent.Slot = slot++;
	}

	// Riding a route behind you (HorseRoutes): on / off its mount, and where its seat is this frame.
	public void SetCompanionRiding(int id, bool on, string clip)
	{
		if (!_companions.TryGetValue(id, out var c)) return;
		c.agent.RideClip = clip;
		_sim.SetRiding(c.agent, on);
	}

	public void PlaceCompanionRider(int id, Vector3 seat, float faceDeg)
	{
		if (!_companions.TryGetValue(id, out var c) || c.agent.Body == null) return;
		_sim.PlaceRider(c.agent, seat, faceDeg);
		// the figure on the saddle now, in the same frame the mount moved (drawn from the body's last spot, it sat a
		// frame behind the seat - ~0.6 m back at a gallop, owner 2026-10-11)
		if (IsInstanceValid(c.view))
		{
			c.view.GlobalPosition = seat;
			c.view.GlobalRotation = new Vector3(0, Mathf.DegToRad(faceDeg) + Mathf.Pi, 0);
		}
	}

	public void RedressCompanion(int id)
	{
		if (_companions.TryGetValue(id, out var c) && IsInstanceValid(c.view)) c.view.Call("redress", c.agent.Record);
	}

	public int[] CompanionIds() => _companions.Keys.ToArray();
	public int BotCount() => _bots.Count + _companions.Count;   // (Perf's live log: drawn gamebots + companions)

	// /pull: your companions set to aggressive go for your target now, attack mode or not (owner 2026-10-11).
	// How many went.
	public int Pull(GodotObject prey)
	{
		int n = 0;
		foreach (var (agent, _) in _companions.Values)
		{
			if (!agent.Alive || agent.Foe == null || agent.State == BotSim.St.Riding) continue;
			if ((string)agent.Foe.Get("stance") != "aggressive") continue;
			_sim.OrderFight(agent, prey, "pulls");
			n++;
		}
		return n;
	}

	// A bot's or companion's health 0..1 (your target bar), -1 when it isn't here.
	public float Health(int id)
	{
		if (_bots.TryGetValue(id, out var p)) return p.Hp;
		if (!_companions.TryGetValue(id, out var b)) return -1f;
		return BotSim.HealthOf(b.agent);
	}

	public Vector3 CompanionPos(int id) => _companions.TryGetValue(id, out var c) && c.agent.Body != null ? c.agent.Body.GlobalPosition : Vector3.Zero;

	// ---------------------------------------------------------------- what the rest of the game asks

	// The bot under a click (its BotView), or null.
	public Node3D Pick(Camera3D cam, Vector2 screen)
	{
		if (_zoneRoot == null || cam == null) return null;
		var from = cam.ProjectRayOrigin(screen);
		var q = PhysicsRayQueryParameters3D.Create(from, from + cam.ProjectRayNormal(screen) * 120f, 1u << 10);
		var hit = _zoneRoot.GetWorld3D().DirectSpaceState.IntersectRay(q);
		if (hit.Count == 0) return null;
		var col = hit["collider"].AsGodotObject() as Node;
		return col != null && col.HasMeta("bot") ? col.GetMeta("bot").As<Node3D>() : null;
	}

	public void SetTarget(int id)
	{
		foreach (var kv in _bots)
			if (IsInstanceValid(kv.Value.View)) kv.Value.View.Set("targeted", kv.Key == id);
		foreach (var (agent, view) in _companions.Values)
			if (IsInstanceValid(view)) view.Set("targeted", agent.Id == id);
		TargetId = id;
	}

	// Your realm's bots in this zone, for the map's green dots (enemy bots never show).
	public Vector3[] FriendlyDots(string realm) => _bots.Values
		.Where(p => p.Realm == realm && IsInstanceValid(p.View)).Select(p => p.View.GlobalPosition).ToArray();

	// Your companions, for their own map dots (owner: not the gamebots' green).
	public Vector3[] CompanionDots() => _companions.Values
		.Where(b => b.agent.Body != null).Select(b => b.agent.Body.GlobalPosition).ToArray();

	// The inspect key (diagnostics): what a bot is doing and its last decisions.
	public string Inspect(int id)
	{
		if (_bots.TryGetValue(id, out var pp))
			return $"{(string)pp.Record["name"]} (level {pp.Level} {(string)pp.Record.GetValueOrDefault("class_name", "")}, {pp.Realm}) - {pp.State} at "
				+ $"{(IsInstanceValid(pp.View) ? pp.View.GlobalPosition.Round() : Vector3.Zero)} (run by the world host: its decisions are in its BOT REPORT / host.log)";
		if (!_companions.TryGetValue(id, out var b)) return "";
		var a = b.agent;
		var p = a.Body?.GlobalPosition ?? Vector3.Zero;
		return $"{a.Name} (level {a.Level} {(string)a.Record["class_name"]}, {a.Realm}) - {a.StateText} / {a.Goal_} at {p.Round()}\n"
			+ string.Join("\n", a.Log.TakeLast(6));
	}

	// Debug (tests): one bot's movement state.
	public string Debug(int id)
	{
		if (!_companions.TryGetValue(id, out var b) || b.agent.Body == null) return "";
		var a = b.agent;
		var p = a.Body.GlobalPosition;
		var tgt = a.Path.Length > 0 && a.PathI < a.Path.Length ? a.Path[a.PathI] : Vector3.Zero;
		var end = a.Path.Length > 0 ? a.Path[^1] : Vector3.Zero;
		return $"pos {p.Round()} grid {a.Zone.Data.Grid(p.X, p.Z):0.0} vel {a.Vel.Round()} vy {a.Vy:0.0} grounded {a.Grounded} "
			+ $"state {a.State} path {a.PathI}/{a.Path.Length} next {tgt.Round()} end {end.Round()} goal {a.Goal.Round()}";
	}

	public int[] Ids() => _bots.Keys.ToArray();

	public int Count => _bots.Count;

	public override void _ExitTree() => ZoneLeft();
}
