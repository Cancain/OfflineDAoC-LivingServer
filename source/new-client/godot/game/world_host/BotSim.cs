// The bots' runtime (bot plan phases 3-4) - the same code in the world host and, for the zone you're in, in the game
// (zone handover). Each bot is a CharacterBody3D moved by the game's own client step (player.gd _client_move: floor
// pick = the height grid + a ray down the floor layer from 64 units up, a leading-edge step-up, walls only for the
// slide, stand within 16 units or fall) with the open-ground shortcut (no fixture floor near: the grid alone; no wall
// near: no slide), and a character - a BotFoe (GDScript) holding its own CharacterState, the same sheet and rules as
// the player's: the zone's Combat resolves its blows and the monsters' blows on it with MeleeMath (owner 2026-10-11:
// bots and players share rules). Never impaired (owner's hard rule): a bot only uses less CPU when it has less to do
// (resting, waiting), never thinks or moves worse.
// The brain (phase 4 so far): pick a monster camp near its level, path there (worker threads), hunt a monster of its
// level there, fight it (swinging at its weapon's speed, monsters fighting back - several at once if they come),
// /sit and rest to full by the player's regeneration, die and release like a player (experience and constitution
// lost, a grave), and level up from its kills.
using Godot;
using System;
using System.Collections.Generic;

namespace MMOEngine;

public sealed class BotAgent
{
	public Godot.Collections.Dictionary Record;    // the bot's character dictionary (saved)
	public int Id, Level = 1, PathI, Repaths;
	public string Name = "", Realm = "";
	public ZoneWorld Zone;
	public CharacterBody3D Body;
	public Vector3 Vel, Goal, CheckPos;
	public float Vy, Timer, NextThink, CheckT, Face;
	public bool Grounded = true;
	public bool Fell;
	public BotSim.St State = BotSim.St.WaitNav;
	public Vector3[] Path = Array.Empty<Vector3>();
	public string ShownState = "";
	public bool ShownDrawn;                        // its weapons shown drawn (BotView.set_drawn)              // the state its BotView last showed (GameBots: set_state on change only)
	public string Goal_ = "", StateText = "";
	public List<string> Log = new();               // the last decisions (diagnostics: the inspect key, hotspots)
	// phase 4: the character and its fight
	public GodotObject Foe;                        // BotFoe: its CharacterState + what the monsters see
	public GodotObject Prey;                       // the NpcState it hunts / fights
	public float SwingLeft, ImpactLeft = -1f, SwingSecs = 3f, ChaseRepath, HuntTries;
	public int Kills, Deaths;
	public bool Sitting, Alive = true;
	public string Anim = "";                       // a one-shot for the view (GameBots): "swing", "flinch", "parry" ...
	// its spell's moments for the view, in order (a cast begun / gone off / spoilt): kept apart from Anim, where a blow in
	// the same moment overwrote "gone off" and the hand glow stayed for good (owner 2026-10-11, Ljelgadi)
	public readonly List<string> CastAnims = new();
	// phase 6: a companion (its leader is the player - BotSim.Leader*)
	public bool Companion, Riding;
	public int Slot;                               // its place in the formation behind you
	public string RideClip = "ride_horse";       // its rider clip while it rides a route (the route's own)
	public float FollowCheck;
	public Vector3 FollowCheckPos;
	public Vector3 LastLeaderPos;                  // where you were at its last think (you moving: it gets up from a rest)
	public GodotObject FoePrey;                    // the prey last told to its BotFoe (BotCaster casts at it)
	// its errand (BotProgress: promote / train / sell / arrows) - walking to a real NPC, maybe over a zone border
	public string ErrandKind = "", ErrandName = "";
	public int ErrandZone = -1, ErrandWant;
	public Vector3 ErrandLocal;
	public bool ErrandCross;
	public double NextErrandCheck;
	// progress, pull watch, camp memory (old server lessons)
	public int CampIdx = -1, CampPullFails, DeathSteps, NoXpDeaths, RouteAvoids;
	public double LevelStartT, LastXpT, LastHitByT, PullT, PullProgressT, LastMoveT, NextRouteScan, LastNoProgressLog;
	public float PullBest, ThinkStep = 0.25f;
	public int PullStartHp;
	public bool Swung;
	public Vector3 LastMovePos;
	public bool ResumeTravel;                      // a fight broke into its trip: back on the way afterwards
	public readonly Dictionary<int, double> BadCamps = new();

	public void Note(string s)
	{
		Log.Add($"{Time.GetTimeStringFromSystem()} {s}");
		if (Log.Count > 20) Log.RemoveAt(0);
	}
}

public sealed class BotSim
{
	public enum St { WaitNav, Pick, WaitPath, Travel, Rest, Wait, Hunt, Fight, Dead, Follow, Riding }

	// the companions' leader - the player (GameBots sets these every frame)
	public Vector3 LeaderPos;
	public float LeaderFace;                       // degrees, the player's convention (forward = -sin, -cos)
	public bool LeaderSitting, LeaderDead;
	public GodotObject Combat;                     // the game's Combat (Combat.companion_pick)
	const float FollowGap = 2.0f;                        // metres from its formation spot before it moves
	const float Leash = 45f;                             // further from you than this, a companion drops its fight

	// the player's own movement rules, read from player.gd (bots and players share rules, owner 2026-10-11 - one owner
	// per rule: a step-up or speed changed for the player changes for the bots)
	static readonly Godot.Collections.Dictionary Rules = GD.Load<GDScript>("res://game/player.gd").GetScriptConstantMap();
	static float Rule(string k) => Rules[k].AsSingle();
	public static readonly float RunSpeed = Rule("RUN_SPEED");
	public static readonly float StepLead = Rule("STEP_LEAD");
	public static readonly float ColliderLift = Rule("COLLIDER_LIFT");
	static readonly float PickLift = Rule("PICK_LIFT");
	static readonly float FloorSnap = Rule("FLOOR_SNAP");
	static readonly float FallHeight = Rule("FALL_HEIGHT");
	static readonly float Gravity = Rule("GRAVITY");
	// ...and the player's melee rules (combat.gd): reach, the front arc, where in the swing the blow lands
	static readonly Godot.Collections.Dictionary CombatRulesMap = GD.Load<GDScript>("res://game/combat/combat.gd").GetScriptConstantMap();
	static readonly float Reach = CombatRulesMap["REACH"].AsSingle();
	static readonly float ReleaseWait = CombatRulesMap["RELEASE_MINIMUM_WAIT"].AsSingle();
	static readonly GDScript FoeScript = GD.Load<GDScript>("res://game/world_host/bot_foe.gd");
	static readonly GDScript Melee = GD.Load<GDScript>("res://game/combat/melee_math.gd");
	static readonly StringName SPos = "pos", SYaw = "yaw", SAlive = "alive", SSitting = "sitting", SMoving = "moving",
		SSheet = "sheet", SHp = "hp", SMaxHp = "max_hp", SPower = "power_pts", SMaxPower = "max_power", SLevel = "level",
		SFighting = "fighting", SName = "name", STargetBot = "target_bot", SPrey = "prey", SHold = "hold", SWantsBuffs = "wants_buffs";
	const float Think = 0.25f;                     // every bot thinks 4 times a second - near you or not
	const int MaxPathsInFlight = 64;
	const float WaypointReached = 0.6f;
	const float HuntRadius = 45f;                  // how far around its camp a bot looks for a monster to fight
	const float ImpactAt = 0.4f;                   // seconds into a swing the blow lands (the player's: clip x HIT_AT)
	const float ChaseDirect = 14f;                 // closer than this to its monster: straight at it, no path

	public readonly List<BotAgent> Agents = new();
	readonly Dictionary<int, BotAgent> _byId = new();
	readonly Queue<BotAgent> _queue = new();
	int _inFlight;
	List<(int id, Vector3[] path)> _results = new();
	readonly object _lock = new();
	readonly PhysicsRayQueryParameters3D _ray = new() { CollisionMask = ZoneWorld.LayerFloor, HitBackFaces = false };
	readonly RandomNumberGenerator _rng = new();
	double _time;
	public int Stuck, Arrived, Paths, Fails, KillsTotal, DeathsTotal, LevelUps;

	public BotSim() => _rng.Randomize();

	public BotWatch Watch;                         // diagnostics (BOT REPORT): events, camps, hotspots
	public bool CanCrossZones;                     // the world host hands a bot to the next zone (errands over a border)
	public Action<BotAgent, int, Vector3> CrossedZone;
	// camps that killed several different bots lately sit out for an hour (old server's camp danger bench)
	static readonly Dictionary<string, (HashSet<int> bots, double since)> CampDeaths = new();
	static readonly Dictionary<string, double> CampBench = new();
	readonly Dictionary<long, int> _campCrowd = new();
	readonly List<(BotAgent a, int zone, Vector3 pos)> _crossings = new();
	double _crowdAt = -1;

	// A saved spot a bot can stand on: inside its zone and not below the ground grid (cities: inside it).
	public static bool ValidSpot(ZoneData z, Vector3 p)
	{
		if (float.IsNaN(p.X) || float.IsNaN(p.Y) || float.IsNaN(p.Z)) return false;
		if (p.X < 0f || p.Z < 0f || p.X > z.SizeM || p.Z > z.SizeM) return false;
		return z.City || p.Y >= z.Grid(p.X, p.Z) - 3f;
	}

	// A bot enters this simulation at its saved location (or its start spot the first time).
	public BotAgent Add(Godot.Collections.Dictionary record, ZoneWorld zone, Vector3 pos, float face, int companionId = -1)
	{
		var info = BotStore.Info(record);
		var a = new BotAgent
		{
			Record = record, Id = companionId >= 0 ? companionId : info["id"].AsInt32(), Companion = companionId >= 0,
			Name = (string)record["name"], Realm = (string)record["realm"],
			Level = record.TryGetValue("level", out var l) ? l.AsInt32() : 1, Zone = zone, Face = face,
			NextThink = (float)(_time + _rng.Randf() * Think),
		};
		var body = new CharacterBody3D { CollisionLayer = 0, CollisionMask = ZoneWorld.LayerWall, Name = $"BotBody{a.Id}" };
		var cap = new CapsuleShape3D { Radius = StepLead, Height = 1.8f - ColliderLift };
		body.AddChild(new CollisionShape3D { Shape = cap, Position = new Vector3(0, ColliderLift + cap.Height * 0.5f, 0) });
		body.Position = pos;                    // set before entering the tree (a global position set during start-up was lost:
		zone.BodyParent.AddChild(body);         // bots at the zone corner, below the ground); the parents sit at the origin
		a.Body = body;
		zone.TouchNow(pos);
		// its character: the same sheet as a player's, in the zone's fights
		a.Foe = FoeScript.New().AsGodotObject();
		a.Foe.Call("setup", a.Id, record);
		a.Foe.Set(SPos, pos);
		a.Level = a.Foe.Call("level").AsInt32();
		a.Alive = a.Foe.Get(SAlive).AsBool();
		a.LevelStartT = a.LastXpT = a.LastMoveT = a.LastNoProgressLog = _time;
		a.LastMovePos = pos;
		a.NextErrandCheck = _time + _rng.RandfRange(1f, 8f);
		zone.Combat?.Call("bot_add", a.Foe);
		Agents.Add(a);
		_byId[a.Id] = a;
		a.Note($"entered {zone.Data.Name} at {pos.Round()} (level {a.Level}, {Hp(a)}/{MaxHp(a)} hit points)");
		return a;
	}

	// A bot leaves this simulation (zone handover / retired): its body goes, its state stays in its record.
	public void Remove(BotAgent a)
	{
		SaveState(a);
		a.Body?.QueueFree();
		a.Body = null;
		if (a.Foe != null)
		{
			a.Zone.Combat?.Call("bot_remove", a.Foe);
			a.Foe.Call("free_sheet");
			a.Foe = null;
		}
		a.Prey = null;
		Agents.Remove(a);
		_byId.Remove(a.Id);
	}

	public void SaveState(BotAgent a)
	{
		if (a.Body == null) return;
		a.Foe?.Call("record");                    // the sheet's numbers (level, experience, health, gear...) into the record
		if (a.Companion) return;                  // (a companion's place is beside you: Companions keeps its record)
		// its place in its zone: the body hangs straight under the zone, so its local position IS the zone position - in
		// the scene or not (a zone leaving the scene reported every body at 0,0,0: 278 bots saved in zone corners under
		// the ground, owner 2026-10-11), and after a border crossing moved the zone
		var p = a.Body.Position;
		a.Record["location"] = new Godot.Collections.Dictionary
		{
			["zone"] = a.Zone.Data.Id, ["pos"] = new Godot.Collections.Array { p.X, p.Y, p.Z }, ["face"] = a.Face,
		};
		var info = BotStore.Info(a.Record);
		info["state"] = a.StateText;
		info["goal"] = a.Goal_;
		info["kills"] = a.Kills;
		info["deaths"] = a.Deaths;
	}

	// Seamless zones: a companion walks over a border with you - its body moves into the new zone's world where it
	// stands (the scene has moved: the new zone is at the origin), its path starts over there.
	public void Rehome(BotAgent a, ZoneWorld zone)
	{
		if (a.Body == null) return;
		var g = a.Body.GlobalPosition;
		a.Body.GetParent()?.RemoveChild(a.Body);
		a.Body.Position = g;                   // the new zone's root sits at the origin
		zone.BodyParent.AddChild(a.Body);
		a.Zone = zone;
		zone.TouchNow(g);
		a.Path = Array.Empty<Vector3>();
		a.PathI = 0;
		a.Foe?.Set(SPos, g);
	}

	// Moved within its zone (its release to a bind spot in this zone).
	public void Place(BotAgent a, Vector3 pos, float face)
	{
		a.Zone.TouchNow(pos);
		a.Body.GlobalPosition = pos;
		a.Face = face;
		a.Vel = Vector3.Zero;
		a.Vy = 0f;
		a.Grounded = true;
		a.Foe?.Set(SPos, pos);
	}

	public ulong ThinkUs, MoveUs;
	public readonly Dictionary<string, ulong> Prof = new();   // debug timing by part (the host's status line)
	ulong _pt;
	void P0() => _pt = Time.GetTicksUsec();
	void P(string k) { ulong n = Time.GetTicksUsec(); Prof[k] = (Prof.TryGetValue(k, out var v) ? v : 0) + n - _pt; _pt = n; }
	double _lastDt;                // time spent thinking / moving since the host's last status line

	public void Tick(double delta)
	{
		_time += delta;
		_lastDt = delta;
		ulong t0 = Time.GetTicksUsec();
		DrainResults();
		foreach (var a in Agents)
			if (_time >= a.NextThink)
			{
				// walking, resting and waiting decide half as often (movement itself stays continuous; a blow is read at
				// the next think) - the old server's lesson: slow only background planning
				a.ThinkStep = !a.Companion && a.State is St.Travel or St.Rest or St.Wait or St.WaitPath ? Think * 2f : Think;
				a.NextThink += a.ThinkStep;
				ThinkOne(a);
			}
		MoveReleased();
		Watch?.Tick(_time, Agents);
		while (_inFlight < MaxPathsInFlight && _queue.Count > 0) Dispatch(_queue.Dequeue());
		ulong t1 = Time.GetTicksUsec();
		ThinkUs += t1 - t0;
		MoveBody();
		if (_crossings.Count > 0)
		{
			var list = _crossings.ToArray();
			_crossings.Clear();
			foreach (var (ca, cz, cp) in list)
				if (_byId.ContainsKey(ca.Id)) CrossedZone?.Invoke(ca, cz, cp);
		}
		MoveUs += Time.GetTicksUsec() - t1;
	}

	void MoveBody()
	{
		float dt = (float)_lastDt;
		foreach (var a in Agents)
		{
			switch (a.State)
			{
				case St.Travel: Move(a, dt); break;
				case St.Hunt:
				case St.Fight: FightTick(a, dt); break;
				case St.Follow: FollowTick(a, dt); break;
			}
		}
	}

	// ---------------------------------------------------------------- the character (BotFoe / CharacterState)

	static GodotObject Sheet(BotAgent a) => a.Foe.Get(SSheet).AsGodotObject();
	static int Hp(BotAgent a) => Sheet(a).Get(SHp).AsInt32();
	static int MaxHp(BotAgent a) => Sheet(a).Get(SMaxHp).AsInt32();
	// What its figure shows: "dead" / "ride:<clip>" / "run" / "sit" / "fight" / "idle" (BotView.set_state).
	public static string ShownStateOf(BotAgent a)
	{
		bool running = a.State == St.Travel || (a.State == St.Hunt && a.Vel != Vector3.Zero)
			|| (a.State == St.Follow && a.Vel != Vector3.Zero);
		return a.State == St.Dead ? "dead" : a.State == St.Riding ? "ride:" + a.RideClip
			: running ? "run" : a.Sitting ? "sit" : a.State == St.Fight || a.State == St.Hunt ? "fight" : "idle";
	}

	// Its weapons out: alive and fighting something (BotView.set_drawn).
	public static bool ShownDrawnOf(BotAgent a) => a.Alive && a.State is St.Fight or St.Hunt && a.Prey != null;

	public static float HealthOf(BotAgent a) => a.Foe == null ? 0f : Math.Clamp((float)Hp(a) / Math.Max(1, MaxHp(a)), 0f, 1f);

	// What happened to it since the last think: monsters coming for it, blows, kills, its death, its sheet's lines
	// ("You raise to level 3!"). Returns true when something attacked it.
	bool ReadEvents(BotAgent a)
	{
		bool attacked = false;
		foreach (var ev in a.Foe.Call("take_events").AsGodotArray())
		{
			var e = ev.AsGodotDictionary();
			switch ((string)e["kind"])
			{
				case "aggro":
					attacked = true;
					a.Note($"{(string)e["by"]} (level {e["level"]}) comes for it");
					break;
				case "hit":
					attacked = true;
					a.LastHitByT = _time;
					a.Anim = "flinch";
					break;
				case "defended":
					attacked = true;
					a.LastHitByT = _time;
					a.Anim = (string)e["how"];
					break;
				case "killed":
					a.Kills++;
					KillsTotal++;
					a.Note($"killed {(string)e["name"]} (level {e["level"]}): {e["xp"]} experience");
					if (e["xp"].AsInt32() > 0 || a.Companion) { a.LastXpT = _time; a.NoXpDeaths = 0; }
					a.CampPullFails = 0;
					Watch?.Camp(a, a.CampIdx, "kill");
					break;
				case "died":
					a.Note($"killed by {(string)e["by"]} (level {e["level"]}){(e["xp_lost"].AsInt32() > 0 ? $", lost {e["xp_lost"]} experience" : "")}");
					if (!a.Companion) OnDeath(a, (string)e["by"], e["level"].AsInt32());
					break;
				case "looted":
					string lt = (string)e["text"];
					a.Note(lt);
					if (lt.Contains("put on")) Watch?.Event(a, "EQUIP", lt);
					break;
				case "released":
					break;
				case "cast":
					AddCast(a, "cast:" + e["effect"].AsInt32());
					break;
				case "fired":
					AddCast(a, "fire:" + e["effect"].AsInt32());
					break;
				case "interrupted":
					AddCast(a, "fizzle:" + e["effect"].AsInt32());
					break;
				case "landed":                                   // a buff / heal on it: the spell's effect on its body
					AddCast(a, "land:" + e["effect"].AsInt32());
					break;
				case "draw":
				case "shoot":
					a.Anim = (string)e["kind"];
					break;
				case "said":
					string t = (string)e["text"];
					if (t.StartsWith("You raise to level"))
					{
						LevelUps++;
						a.Note(t);
						if (!a.Companion)
						{
							a.Level = a.Foe.Call("level").AsInt32();
							Watch?.Event(a, "LEVEL", t, 0, ("minutes", (int)((_time - a.LevelStartT) / 60)));
							a.LevelStartT = _time;
							a.DeathSteps = Math.Max(0, a.DeathSteps - 1);     // a level gained: braver again
						}
					}
					else if (t.StartsWith("You cannot raise") || t.StartsWith("A grave") || t.StartsWith("You've lost"))
						a.Note(t);
					break;
			}
		}
		return attacked;
	}

	// The monster now fighting it, if any (the first on Combat's list).
	GodotObject Attacker(BotAgent a)
	{
		var list = a.Zone.Combat?.Call("bot_attackers", a.Foe).AsGodotArray();
		return list != null && list.Count > 0 ? list[0].AsGodotObject() : null;
	}

	static bool PreyAlive(BotAgent a) => a.Prey != null && GodotObject.IsInstanceValid(a.Prey) && a.Prey.Get(SAlive).AsBool();

	void StandUp(BotAgent a)
	{
		if (!a.Sitting) return;
		a.Sitting = false;
		a.Foe.Set(SSitting, false);
	}

	void SitDown(BotAgent a)
	{
		a.Sitting = true;
		a.Foe.Set(SSitting, true);
	}

	// A spell moment for its view (GameBots empties the list each frame; the world host has no views, so it is kept short
	// - unbounded, every cast of 3,000 bots piled up there).
	static void AddCast(BotAgent a, string s)
	{
		if (a.CastAnims.Count >= 8) a.CastAnims.RemoveAt(0);
		a.CastAnims.Add(s);
	}

	// An order from you (/pull): it goes for this monster now.
	public void OrderFight(BotAgent a, GodotObject prey, string why) => StartFight(a, prey, why);

	void StartFight(BotAgent a, GodotObject prey, string why)
	{
		StandUp(a);
		// a fight on the way (a road monster, an attack): the trip - and its errand - goes on afterwards
		a.ResumeTravel = !a.Companion && a.State is St.Travel or St.WaitPath;
		a.Prey = prey;
		a.PullT = a.PullProgressT = _time;
		a.PullBest = a.Body != null ? Flat(a.Body.GlobalPosition, prey.Get(SPos).AsVector3()) : 0f;
		a.PullStartHp = prey.Get(SHp).AsInt32();
		a.Swung = false;
		a.FoePrey = prey;
		a.Foe.Set(SPrey, prey);
		a.State = St.Hunt;
		a.ChaseRepath = 0f;
		a.SwingLeft = 0.6f;
		Set(a, "FIGHTING", "");
		a.SwingSecs = Melee.Call("swing_seconds", Sheet(a), Melee.Call("weapon", Sheet(a))).AsSingle();
		a.Note($"{why}: {(string)prey.Get("spawn").AsGodotDictionary()["name"]} (level {prey.Get(SLevel)})");
	}

	// ---------------------------------------------------------------- brain

	void ThinkOne(BotAgent a)
	{
		if (a.Body == null || a.Foe == null) return;
		P0();
		var here = a.Body.GlobalPosition;
		a.Foe.Set(SPos, here);
		a.Foe.Set(SYaw, Mathf.DegToRad(a.Face));
		a.Foe.Set(SMoving, a.State == St.Travel || ((a.State == St.Hunt || a.State == St.Follow) && a.Vel != Vector3.Zero));
		if (a.FoePrey != a.Prey)
		{
			a.FoePrey = a.Prey;
			a.Foe.Set(SPrey, a.Prey);
		}
		P("think: sets");
		bool attacked = ReadEvents(a);
		P("think: events");
		a.Level = a.Foe.Call("level").AsInt32();
		bool alive = a.Foe.Get(SAlive).AsBool();
		P("think: level+alive");
		if (a.Companion)
		{
			CompanionThink(a, alive);
			return;
		}
		if (!alive && a.State != St.Dead)
		{
			a.Alive = false;
			a.State = St.Dead;
			a.Deaths++;
			DeathsTotal++;
			a.Timer = ReleaseWait + _rng.RandfRange(3f, 15f);   // /release after the minimum wait (a player reads, then types)
			a.Prey = null;
			a.Vel = Vector3.Zero;
			a.Sitting = false;
			Set(a, "DEAD", "");
			return;
		}
		Watchdog(a, here);
		if (a.State is St.Hunt or St.Fight && PreyAlive(a) && PullWatch(a, here))
			return;
		// something came for it while it walks, rests or waits: it fights back (the player's way - no running off yet)
		if (attacked && a.State is St.Pick or St.WaitPath or St.Travel or St.Rest or St.Wait)
		{
			var att = Attacker(a);
			if (att != null) { StartFight(a, att, "attacked by"); return; }
		}
		switch (a.State)
		{
			case St.WaitNav:
				Set(a, "WAITING", "");
				if (a.Zone.NavReady) a.State = St.Pick;
				break;
			case St.Pick:
			{
				// hurt or drained: /sit and rest first
				if (NeedsRest(a)) { BeginRest(a); break; }
				// an errand first: its advanced class at level 5, training its points, selling a full bag (between camps,
				// never mid-grind), arrows (bought, never free) - BotProgress; maybe over a zone border
				if (_time >= a.NextErrandCheck)
				{
					a.NextErrandCheck = _time + 30.0 + _rng.RandfRange(0f, 10f);
					var er = a.Zone.Combat?.Call("bot_errand", a.Foe, a.Zone.Data.Id).AsGodotDictionary();
					if (er != null && er.Count > 0 && StartErrand(a, er))
						break;
				}
				// off the walkable ground (the map still joining there): wait, never a straight line across the zone
				P0();
				var on = a.Zone.ClosestPoint(here);
				P("think: pick closest");
				if (new Vector2(on.X - here.X, on.Z - here.Z).Length() > 15f)
				{
					a.State = St.Wait;
					a.Timer = 5f;
					Set(a, "WAITING", "");
					break;
				}
				ClearErrand(a);                                 // (an errand from before a death is looked for again)
				a.ResumeTravel = false;
				P0();
				a.Goal = a.Zone.ClosestPoint(PickCamp(a));
				a.Goal_ = "LEVELING";
				a.CampPullFails = 0;
				a.RouteAvoids = 0;
				Watch?.Camp(a, a.CampIdx, "attempt");
				P("think: pick camp");
				Request(a);
				P("think: request");
				break;
			}
			case St.Travel:
				a.CheckT += a.ThinkStep;
				if (a.CheckT >= 4f)
				{
					float moved = here.DistanceTo(a.CheckPos);
					a.CheckT = 0f;
					a.CheckPos = here;
					if (moved < 1f)
					{
						a.Repaths++;
						a.Note($"no progress at {here.Round()} (try {a.Repaths})");
						if (a.Repaths >= 3)
						{
							a.Note($"STUCK at {here.Round()} - wiggling out");
							var near = a.Zone.ClosestPoint(here);
							var next = a.PathI < a.Path.Length ? a.Path[a.PathI] : here;
							a.Note($"   next waypoint {next.Round()} ({here.DistanceTo(next):0.0} m), path {a.PathI}/{a.Path.Length}, nearest walkable {near.Round()} ({here.DistanceTo(near):0.0} m), grounded {a.Grounded}, wall near {a.Zone.Data.NearWall(here.X, here.Z)}");
							a.Repaths = 0;
							Unstick(a, here);
						}
						else Request(a);
					}
				}
				break;
			case St.Wait:
				a.Timer -= a.ThinkStep;
				if (a.Timer <= 0f) a.State = St.Pick;
				break;
			case St.Rest:
				// sitting until whole again (the player's regeneration - BotFoe.regen)
				if (!NeedsRest(a, 0.98f))
				{
					StandUp(a);
					a.Note($"rested: {Hp(a)}/{MaxHp(a)} hit points");
					a.State = St.Hunt;
					a.Prey = null;
					a.HuntTries = 0;
				}
				break;
			case St.Hunt:
				if (!PreyAlive(a))
				{
					var att = Attacker(a);
					if (att != null) { StartFight(a, att, "turns on"); break; }
					if (NeedsRest(a)) { BeginRest(a); break; }
					if (a.ResumeTravel)
					{
						a.ResumeTravel = false;                     // the fight on the road is over: on to where it was going
						a.HuntTries = 0;
						Request(a);
						break;
					}
					P0();
					// by con, as the old server's solo bots: green to yellow (NaturalMaximumTargetCon - yellow is its own
					// level, orange already +1 at low levels: owner 2026-10-11 saw bots fight orange monsters); a death
					// steps the hardest con down one, never below green (MaximumTargetCon)
					int hi = Math.Max(-2, 0 - a.DeathSteps);
					var prey = a.Zone.Combat?.Call("bot_prey", a.Foe, here, HuntRadius, -2, hi).AsGodotObject();
					P("think: bot_prey");
					if (prey != null) { StartFight(a, prey, "hunting"); break; }
					a.HuntTries++;
					Set(a, "HUNTING", "");
					if (a.HuntTries >= 8)                       // nothing of its level here (2 s): another camp
					{
						a.HuntTries = 0;
						AbandonCamp(a, "nothing of its level left (outleveled or emptied)", 900);
					}
				}
				break;
			case St.Fight:
				if (!PreyAlive(a))
				{
					a.State = St.Hunt;
					a.Prey = null;
				}
				break;
			case St.Dead:
				a.Timer -= Think;
				if (a.Timer <= 0f) Release(a);
				break;
		}
	}

	// Below 60% health (or, with power, below 40% of it): time to sit. `full` - rested enough to get up.
	bool NeedsRest(BotAgent a, float full = 0f)
	{
		Prof["needsrest calls"] = (Prof.TryGetValue("needsrest calls", out var nc) ? nc : 0) + 1;
		var s = Sheet(a);
		int hp = s.Get(SHp).AsInt32(), mhp = Math.Max(1, s.Get(SMaxHp).AsInt32());
		int pw = s.Get(SPower).AsInt32(), mpw = s.Get(SMaxPower).AsInt32();
		if (full > 0f)
			return hp < mhp * full || (mpw > 0 && pw < mpw * full);
		return hp < mhp * 0.6f || (mpw > 0 && pw < mpw * 0.4f);
	}

	void BeginRest(BotAgent a)
	{
		a.State = St.Rest;
		a.Vel = Vector3.Zero;
		a.Prey = null;
		SitDown(a);
		Set(a, "RESTING", "");
		a.Note($"sits to rest: {Hp(a)}/{MaxHp(a)} hit points");
	}

	// Released (the player's release: losses, full health, to its bind spot or - never bound - its start).
	public Action<BotAgent, Godot.Collections.Dictionary> Released;   // the owner moves it (another zone: WorldHost)

	void Release(BotAgent a)
	{
		var bind = a.Zone.Combat?.Call("bot_release", a.Foe, a.Body.GlobalPosition).AsGodotDictionary() ?? new();
		a.Alive = true;
		a.State = St.Pick;
		Set(a, "RELEASED", "");
		a.Note("released its corpse unto death");
		if (a.NoXpDeaths >= 2)
		{
			// repeated deaths with no experience between: a pause before the next try (old server: no tight
			// release -> walk -> death loop)
			a.State = St.Wait;
			a.Timer = Math.Min(300f, 60f * (a.NoXpDeaths - 1));
			Watch?.Event(a, "DEATH_PAUSE", $"{a.NoXpDeaths} deaths without experience: waits {a.Timer:0} s", 0);
		}
		_released.Add((a, bind));                // moved after the think loop (the owner may take it out of the list)
	}

	readonly List<(BotAgent a, Godot.Collections.Dictionary bind)> _released = new();

	void MoveReleased()
	{
		if (_released.Count == 0) return;
		var list = _released.ToArray();
		_released.Clear();
		foreach (var (a, bind) in list)
			if (_byId.ContainsKey(a.Id)) Released?.Invoke(a, bind);
	}

	// ---------------------------------------------------------------- a companion (phase 6)

	// Its stance picks what it fights (Combat.companion_pick); otherwise it keeps its place behind you and sits when
	// you sit; dead, it lies where it fell (the inn's healer brings it back - Companions); riding, the route carries it.
	void CompanionThink(BotAgent a, bool alive)
	{
		if (!alive)
		{
			if (a.State != St.Dead)
			{
				a.State = St.Dead;
				a.Alive = false;
				a.Prey = null;
				a.Vel = Vector3.Zero;
				a.Sitting = false;
				a.Deaths++;
				DeathsTotal++;
				Set(a, "DEAD", "");
			}
			return;
		}
		if (a.State == St.Riding) return;
		var here = a.Body.GlobalPosition;
		string stance = (string)a.Foe.Get("stance");
		float toLeader = new Vector2(here.X - LeaderPos.X, here.Z - LeaderPos.Z).Length();
		// fighting: carry on while it lives and you're near; an aggressive companion switches to what you attack
		if ((a.State == St.Hunt || a.State == St.Fight) && PreyAlive(a) && toLeader < Leash && stance != "passive")
		{
			if (stance == "aggressive" && Combat != null && Combat.Get("attack_mode").AsBool())
			{
				var mine = Combat.Call("companion_pick", a.Foe, stance).AsGodotObject();
				if (mine != null && mine != a.Prey) StartFight(a, mine, "assists you on");
			}
			return;
		}
		if (toLeader < Leash && stance != "passive" && Combat != null)
		{
			var foe = Combat.Call("companion_pick", a.Foe, stance).AsGodotObject();
			if (foe != null) { StartFight(a, foe, stance == "aggressive" ? "attacks" : "defends against"); return; }
		}
		a.Prey = null;
		if (a.State != St.Follow)
		{
			a.State = St.Follow;
			a.Path = Array.Empty<Vector3>();
			Set(a, "FOLLOWING", "");
		}
		var spot = FormationSpot(a);
		bool there = new Vector2(here.X - spot.X, here.Z - spot.Z).Length() < FollowGap + 1f;
		// it sits when you sit, and to rest when it needs to (low health or power - up again when full) unless you're on
		// the move (owner 2026-10-11: "companion bots will rest if they need to unless the player starts moving")
		bool leaderMoving = new Vector2(LeaderPos.X - a.LastLeaderPos.X, LeaderPos.Z - a.LastLeaderPos.Z).Length() > 0.2f;
		a.LastLeaderPos = LeaderPos;
		bool restWant = a.Sitting ? NeedsRest(a, 0.98f) : NeedsRest(a);
		bool sitWanted = there && (LeaderSitting || (restWant && !leaderMoving));
		// a missing buff goes up before it sits, and it never sits mid-cast (old server: the sit-wake-sit loop)
		if (sitWanted && !a.Sitting && (a.Foe.Get(SHold).AsSingle() < 0f || a.Foe.Get(SWantsBuffs).AsBool()))
			sitWanted = false;
		if (sitWanted && !a.Sitting)
		{
			SitDown(a);
			if (!LeaderSitting) a.Note($"sits to rest: {Hp(a)}/{MaxHp(a)} hit points");
		}
		else if (!sitWanted && a.Sitting) StandUp(a);
		// no progress toward you for 3 s, or far off: a path around what is in the way
		a.FollowCheck += Think;
		if (a.FollowCheck >= 3f)
		{
			a.FollowCheck = 0f;
			if ((!there && here.DistanceTo(a.FollowCheckPos) < 1f) || toLeader > 25f)
			{
				a.Goal = spot;
				ChasePath(a);
			}
			a.FollowCheckPos = here;
		}
	}

	// The formation's turn: the way you last walked, not your facing - turning on the spot moves nobody.
	Vector3 _formFrom;
	float _formFace;
	bool _formInit;

	// Its place behind you: two abreast, rows 2 m apart, turned with the way you walk.
	Vector3 FormationSpot(BotAgent a)
	{
		if (!_formInit)
		{
			_formInit = true;
			_formFrom = LeaderPos;
			_formFace = LeaderFace;
		}
		var mv = new Vector2(LeaderPos.X - _formFrom.X, LeaderPos.Z - _formFrom.Z);
		if (mv.Length() > 1.5f)
		{
			_formFace = Mathf.RadToDeg(Mathf.Atan2(-mv.X, -mv.Y));   // the way you walked (the player's convention)
			_formFrom = LeaderPos;
		}
		float f = Mathf.DegToRad(_formFace);
		var back = new Vector3(Mathf.Sin(f), 0, Mathf.Cos(f));     // behind the player (who faces -sin, -cos)
		var side = new Vector3(back.Z, 0, -back.X);
		int row = a.Slot / 2;
		float lateral = a.Slot % 2 == 0 ? 1.8f : -1.8f;
		return LeaderPos + back * (2.5f + row * 2.0f) + side * lateral;
	}

	void FollowTick(BotAgent a, float dt)
	{
		var pos = a.Body.GlobalPosition;
		var spot = FormationSpot(a);
		var to = new Vector3(spot.X - pos.X, 0f, spot.Z - pos.Z);
		float dist = to.Length();
		bool casting = a.Foe != null && a.Foe.Get(SHold).AsSingle() < 0f;
		if (dist < FollowGap || a.Sitting || (casting && dist < 10f))   // (a cast is finished unless you've really gone)
		{
			a.Vel = Vector3.Zero;
			a.Path = Array.Empty<Vector3>();
			if (!a.Grounded) { a.Vy -= Gravity * dt; ClientMove(a, dt); }
			a.Face = Mathf.RadToDeg(Mathf.LerpAngle(Mathf.DegToRad(a.Face), Mathf.DegToRad(LeaderFace), Math.Min(1f, dt * 4f)));
			return;
		}
		if (a.Path.Length > 0 && dist > 6f)
		{
			MoveAlong(a, dt);
			if (a.PathI >= a.Path.Length) a.Path = Array.Empty<Vector3>();
		}
		else
		{
			a.Vel = to / dist * RunSpeed;                        // the player's run speed - never faster
			if (a.Grounded) a.Vy = 0f; else a.Vy -= Gravity * dt;
			a.Zone.Touch(pos);
			ClientMove(a, dt);
		}
		if (a.Vel.LengthSquared() > 0.01f) a.Face = Mathf.RadToDeg(Mathf.Atan2(-a.Vel.X, -a.Vel.Z));
		a.Foe.Set(SPos, a.Body.GlobalPosition);
		a.Foe.Set(SYaw, Mathf.DegToRad(a.Face));
	}

	// On a route's mount (HorseRoutes, through GameBots): the body sits where the mount carries it.
	public void SetRiding(BotAgent a, bool on)
	{
		if (on == (a.State == St.Riding)) return;
		a.Riding = on;
		a.Foe?.Set("riding", on);
		a.Prey = null;
		a.Vel = Vector3.Zero;
		a.Sitting = false;
		a.Foe?.Set(SSitting, false);
		a.Path = Array.Empty<Vector3>();
		a.State = on ? St.Riding : St.Follow;
		Set(a, on ? "RIDING" : "FOLLOWING", "");
	}

	public void PlaceRider(BotAgent a, Vector3 seat, float faceDeg)
	{
		a.Body.GlobalPosition = seat;
		a.Face = faceDeg;
		a.Vy = 0f;
		a.Grounded = true;
		a.Zone.Touch(seat);
		a.Foe?.Set(SPos, seat);
		a.Foe?.Set(SYaw, Mathf.DegToRad(faceDeg));
	}

	// ---------------------------------------------------------------- the fight (every tick while hunting / fighting)

	void FightTick(BotAgent a, float dt)
	{
		P0();
		if (!PreyAlive(a)) { a.Vel = Vector3.Zero; if (a.Companion) a.State = St.Follow; return; }
		var pos = a.Body.GlobalPosition;
		var at = a.Prey.Get(SPos).AsVector3();
		P("fight: prey reads");
		var to = new Vector3(at.X - pos.X, 0f, at.Z - pos.Z);
		float dist = to.Length();
		if (dist > 0.05f) a.Face = Mathf.RadToDeg(Mathf.Atan2(-to.X, -to.Z));   // faces it (the player's /face)
		a.Foe.Set(SPos, pos);
		a.Foe.Set(SYaw, Mathf.DegToRad(a.Face));
		P("fight: sets");
		// the blow of a swing already started lands (or misses) - even if it stepped back meanwhile, as the player's
		if (a.ImpactLeft >= 0f)
		{
			a.ImpactLeft -= dt;
			if (a.ImpactLeft < 0f)
			{
				P0();
				var r = a.Zone.Combat.Call("bot_swing", a.Foe, a.Prey).AsGodotDictionary();
				a.Swung = true;
				P("fight: bot_swing");
				if (r.TryGetValue("killed", out var k) && k.AsBool())
				{
					a.Prey = null;
					a.State = a.Companion ? St.Follow : St.Hunt;
					a.Vel = Vector3.Zero;
					return;
				}
			}
		}
		float hold = a.Foe.Get(SHold).AsSingle();
		if (hold < 0f)
		{
			// casting or drawing its bow: stands where it is, facing it (a step spoils the spell - the player's rule)
			a.State = St.Fight;
			a.Vel = Vector3.Zero;
			a.Path = Array.Empty<Vector3>();
			if (!a.Grounded) { a.Vy -= Gravity * dt; ClientMove(a, dt); }
			return;
		}
		if (dist > (hold > 0f ? hold : Reach * 0.9f))
		{
			// out of reach: run to it - straight at it close by, along a path when far (around walls and buildings)
			a.State = St.Hunt;
			if (dist <= ChaseDirect || a.Path.Length == 0)
			{
				a.Vel = to / dist * RunSpeed;
				if (a.Grounded) a.Vy = 0f; else a.Vy -= Gravity * dt;
				a.Zone.Touch(pos);
				ClientMove(a, dt);
			}
			else MoveAlong(a, dt);
			a.ChaseRepath -= dt;
			if (dist > ChaseDirect && a.ChaseRepath <= 0f)
			{
				a.ChaseRepath = 1f;
				a.Goal = at;
				ChasePath(a);
			}
			a.SwingLeft = Math.Max(a.SwingLeft - dt, 0f);
			return;
		}
		// in reach, facing it: swing at the weapon's speed (in spell or bow range: stands there - BotCaster fights)
		a.State = St.Fight;
		a.Vel = Vector3.Zero;
		a.Path = Array.Empty<Vector3>();
		if (!a.Grounded) { a.Vy -= Gravity * dt; ClientMove(a, dt); }
		if (hold > 0f) return;
		a.SwingLeft -= dt;
		if (a.SwingLeft <= 0f && a.ImpactLeft < 0f)
		{
			a.SwingLeft = a.SwingSecs;
			a.ImpactLeft = ImpactAt;
			a.Anim = "swing";
		}
	}

	// A chase path (worker thread) toward a monster beyond direct reach; the fight keeps running meanwhile.
	void ChasePath(BotAgent a)
	{
		int id = a.Id;
		Rid map = a.Zone.Map;
		var from = a.Body.GlobalPosition;
		var to = a.Goal;
		_inFlight++;
		WorkerThreadPool.AddTask(Callable.From(() =>
		{
			var q = new NavigationPathQueryParameters3D { Map = map, StartPosition = from, TargetPosition = to };
			var r = new NavigationPathQueryResult3D();
			NavigationServer3D.QueryPath(q, r);
			var path = r.Path;
			lock (_lock) _results.Add((-id - 1, path));            // negative: a chase path (keeps its state)
		}));
	}

	void MoveAlong(BotAgent a, float dt)
	{
		var pos = a.Body.GlobalPosition;
		if (a.PathI >= a.Path.Length) { a.Path = Array.Empty<Vector3>(); return; }
		var target = a.Path[a.PathI];
		var flat = new Vector3(target.X - pos.X, 0f, target.Z - pos.Z);
		if (flat.Length() < WaypointReached) { a.PathI++; return; }
		a.Vel = flat.Normalized() * RunSpeed;
		if (a.Grounded) a.Vy = 0f; else a.Vy -= Gravity * dt;
		a.Zone.Touch(pos);
		ClientMove(a, dt);
	}

	public Action<BotAgent, Vector3> StuckAt;       // diagnostics: the hotspot report

	static readonly Vector3[] Dirs =
	{
		new(1, 0, 0), new(-1, 0, 0), new(0, 0, 1), new(0, 0, -1),
		new(0.707f, 0, 0.707f), new(-0.707f, 0, 0.707f), new(0.707f, 0, -0.707f), new(-0.707f, 0, -0.707f),
	};

	// Wedged against a wall with the path's next step behind it: wiggle out as a player would - the first of eight
	// directions the body can really move 2 m into (no teleport), walked, then a fresh path. No free direction: the
	// spot goes into the hotspot report and the bot waits there (no retry spam) until something changes.
	void Unstick(BotAgent a, Vector3 p)
	{
		Stuck++;
		StuckAt?.Invoke(a, p);
		Watch?.Event(a, "STUCK", a.Log.Count > 0 ? a.Log[^1].Trim() : "", 30);
		int start = (int)(_rng.Randi() % 8);
		for (int k = 0; k < 8; k++)
		{
			var d = Dirs[(start + k) % 8];
			var from = a.Body.GlobalTransform;
			from.Origin += new Vector3(0, 0.05f, 0);
			if (a.Body.TestMove(from, d * 2f)) continue;          // blocked that way
			a.Path = new[] { p + d * 2f };
			a.PathI = 0;
			a.State = St.Travel;
			a.CheckT = 0f;
			a.CheckPos = p;
			a.Note($"   wiggling {d.Round()} to get free");
			return;
		}
		a.Note("   no free direction - wedged; waiting");
		Watch?.Event(a, "WEDGED", "no free direction", 60);
		a.State = St.Wait;
		a.Timer = 300f;
		Set(a, "WEDGED", "");
	}

	void Set(BotAgent a, string state, string goal)
	{
		a.StateText = state;
		if (goal != "") a.Goal_ = goal;
	}

	// A camp near its level (one lower for each recent death), not one it failed at lately, not one benched for killing
	// several bots, and not crowded (each bot already there counts against it - old server: spread the population).
	Vector3 PickCamp(BotAgent a)
	{
		var z = a.Zone.Data;
		var here = a.Body.GlobalPosition;
		a.CampIdx = -1;
		if (z.Camps.Length == 0)
			return z.Spots.Length > 0 ? z.Spots[_rng.Randi() % z.Spots.Length] : here;
		if (_time - _crowdAt > 2.0)
		{
			_crowdAt = _time;
			_campCrowd.Clear();
			foreach (var o in Agents)
				if (o.CampIdx >= 0 && o.Zone != null)
				{
					long key = (long)o.Zone.Data.Id << 20 | (uint)o.CampIdx;
					_campCrowd[key] = (_campCrowd.TryGetValue(key, out int n) ? n : 0) + 1;
				}
		}
		int target = a.Level - a.DeathSteps;
		int best = -1;
		float bestScore = float.PositiveInfinity;
		for (int k = 0; k < 16; k++)
		{
			int i = (int)(_rng.Randi() % (uint)z.Camps.Length);
			if (a.BadCamps.TryGetValue(i, out double until) && until > _time) continue;
			if (CampBench.TryGetValue($"{z.Id}:{i}", out double bench) && bench > _time) continue;
			_campCrowd.TryGetValue((long)z.Id << 20 | (uint)i, out int crowd);
			float score = Math.Abs(z.CampLevels[i] - target) * 30f + z.Camps[i].DistanceTo(here) * 0.1f + crowd * 15f;
			if (score < bestScore) { bestScore = score; best = i; }
		}
		if (best < 0)
			best = (int)(_rng.Randi() % (uint)z.Camps.Length);      // (everything ruled out: any camp rather than none)
		a.CampIdx = best;
		return z.Camps[best] + new Vector3(_rng.RandfRange(-4, 4), 0, _rng.RandfRange(-4, 4));
	}

	static float Flat(Vector3 p, Vector3 q) => new Vector2(p.X - q.X, p.Z - q.Z).Length();

	void AbandonCamp(BotAgent a, string why, double forSeconds)
	{
		if (a.CampIdx >= 0)
		{
			a.BadCamps[a.CampIdx] = _time + forSeconds;
			Watch?.Camp(a, a.CampIdx, "abandon", why);
		}
		Watch?.Event(a, "CAMP_ABANDON", why);
		a.Note($"leaves its camp: {why}");
		a.Prey = null;
		a.State = St.Pick;
	}

	// A death (old server lessons): the hardest con it picks steps down one; that camp is avoided for 30 minutes; a camp
	// several different bots died at within an hour is benched for an hour for everyone.
	void OnDeath(BotAgent a, string by, int byLevel)
	{
		bool traveling = a.State is St.Travel or St.WaitPath;
		if (_time - a.LastXpT > 600) a.NoXpDeaths++;
		a.DeathSteps = Math.Min(3, a.DeathSteps + 1);
		Watch?.Event(a, "DEATH", $"killed by {by} (level {byLevel}) {(traveling ? "on the way" : "at its camp")}", 0,
			("killer", by), ("killer_level", byLevel), ("traveling", traveling));
		if (a.CampIdx < 0) return;
		Watch?.Camp(a, a.CampIdx, "death");
		a.BadCamps[a.CampIdx] = _time + 1800;
		string key = $"{a.Zone.Data.Id}:{a.CampIdx}";
		if (!CampDeaths.TryGetValue(key, out var d) || _time - d.since > 3600)
			d = (new HashSet<int>(), _time);
		d.bots.Add(a.Id);
		CampDeaths[key] = d;
		if (d.bots.Count >= 3)
		{
			CampBench[key] = _time + 3600;
			CampDeaths.Remove(key);
			Watch?.Event(a, "CAMP_BENCHED", $"camp {key} killed {d.bots.Count} different bots within the hour: benched for an hour", 0);
		}
	}

	// The pull watch (old server: every pull is watched): a pull that never lands a blow, never takes a hit and stops
	// closing in is given up - that monster is skipped for 90 s; three such at one camp and it picks another camp.
	bool PullWatch(BotAgent a, Vector3 here)
	{
		if (a.Companion) return false;
		var pp = a.Prey.Get(SPos).AsVector3();
		float d = Flat(here, pp);
		bool contact = a.Swung || a.Prey.Get(SHp).AsInt32() < a.PullStartHp || _time - a.LastHitByT < 6.0;
		if (contact) return false;
		if (d < a.PullBest - 1.5f)
		{
			a.PullBest = d;
			a.PullProgressT = _time;
		}
		if (_time - a.PullProgressT < 12.0 && _time - a.PullT < 45.0) return false;
		string name = (string)a.Prey.Get("spawn").AsGodotDictionary()["name"];
		a.Foe.Call("skip_prey", a.Prey, 90);
		Watch?.Event(a, "PULL_TIMEOUT", $"never reached {name}", 30, ("target", name), ("distance", Mathf.Round(d)),
			("height", Mathf.Round(pp.Y - here.Y)));
		Watch?.Camp(a, a.CampIdx, "timeout");
		a.Note($"gives up on {name}: never got to it ({d:0} m)");
		a.Prey = null;
		a.Vel = Vector3.Zero;
		a.Path = Array.Empty<Vector3>();
		a.State = St.Hunt;
		a.HuntTries = 0;
		if (++a.CampPullFails >= 3)
		{
			a.CampPullFails = 0;
			AbandonCamp(a, "3 pulls in a row never reached their monster", 1800);
		}
		return true;
	}

	// The watchdog (old server: separate movement and progress clocks; here they only log and nudge, never teleport):
	// no movement for 10 minutes outside rest, waits and fights - logged, wiggled free, a new goal; no experience for 30
	// minutes while alive - logged (BOT REPORT lists it).
	void Watchdog(BotAgent a, Vector3 here)
	{
		if (a.Companion || !a.Alive) return;
		if (here.DistanceSquaredTo(a.LastMovePos) > 9f || a.State is St.Rest or St.Dead or St.Fight || a.Sitting)
		{
			a.LastMovePos = here;
			a.LastMoveT = _time;
		}
		else if (_time - a.LastMoveT > 600)
		{
			Watch?.Event(a, "STALL", $"no movement for 10 minutes ({a.State}, {a.Goal_})", 600);
			a.LastMoveT = _time;
			ClearErrand(a);
			Unstick(a, here);
			if (a.State != St.Travel) a.State = St.Pick;
		}
		if (_time - a.LastXpT > 1800 && _time - a.LastNoProgressLog > 1800)
		{
			a.LastNoProgressLog = _time;
			Watch?.Event(a, "NO_PROGRESS", $"no experience for {(int)((_time - a.LastXpT) / 60)} minutes ({a.State}, {a.Goal_})", 0);
		}
	}

	// ---------------------------------------------------------------- errands (BotProgress)

	bool StartErrand(BotAgent a, Godot.Collections.Dictionary er)
	{
		string kind = (string)er["kind"];
		int zone = er["zone"].AsInt32();
		var local = er["local"].AsVector3();
		var here = a.Body.GlobalPosition;
		var size = a.Zone.Data.SizeM;
		if (zone == a.Zone.Data.Id)
		{
			a.ErrandCross = false;
			a.Goal = a.Zone.ClosestPoint(er["pos"].AsVector3());
		}
		else
		{
			if (!CanCrossZones) return false;
			// toward the border on the straight line to the NPC, 2 m inside it; the next zone takes it over there
			var dir = local - here;
			dir.Y = 0f;
			float t = 1f;
			const float m = 2f;
			if (dir.X > 0.01f) t = Math.Min(t, (size - m - here.X) / dir.X);
			if (dir.X < -0.01f) t = Math.Min(t, (m - here.X) / dir.X);
			if (dir.Z > 0.01f) t = Math.Min(t, (size - m - here.Z) / dir.Z);
			if (dir.Z < -0.01f) t = Math.Min(t, (m - here.Z) / dir.Z);
			var edge = here + dir * Math.Max(0f, t);
			edge.Y = a.Zone.Data.Grid(edge.X, edge.Z);
			a.ErrandCross = true;
			a.Goal = a.Zone.ClosestPoint(edge);
		}
		a.ErrandKind = kind;
		a.ErrandZone = zone;
		a.ErrandWant = er["want"].AsInt32();
		a.ErrandLocal = local;
		a.ErrandName = (string)er["name"];
		a.Goal_ = kind.ToUpperInvariant();
		a.CampIdx = -1;
		a.Note($"errand ({kind}): to {a.ErrandName}{(a.ErrandCross ? $" in zone {zone}" : "")}");
		Watch?.Event(a, "ERRAND", $"{kind}: to {a.ErrandName}{(a.ErrandCross ? $" (zone {zone})" : "")}", 120);
		Request(a);
		return true;
	}

	void ClearErrand(BotAgent a)
	{
		a.ErrandKind = "";
		a.ErrandCross = false;
	}

	void FailErrand(BotAgent a, string why)
	{
		Watch?.Event(a, "ERRAND_FAIL", $"{a.ErrandKind} at {a.ErrandName}: {why}", 60);
		a.Foe?.Call("block_errand", a.ErrandKind, 1800);
		ClearErrand(a);
		a.State = St.Pick;
	}

	void ArriveErrand(BotAgent a)
	{
		var here = a.Body.GlobalPosition;
		if (a.ErrandCross)
		{
			var size = a.Zone.Data.SizeM;
			float edge = Math.Min(Math.Min(here.X, size - here.X), Math.Min(here.Z, size - here.Z));
			if (edge > 8f) { FailErrand(a, "the way to the border ends short of it"); return; }
			var dir = a.ErrandLocal - here;
			dir.Y = 0f;
			var beyond = here + dir.Normalized() * (edge + 3f);
			var to = a.Zone.Combat?.Call("bot_zone_at", a.Zone.Data.Id, beyond).AsGodotDictionary();
			if (to == null || to.Count == 0 || to["zone"].AsInt32() == a.Zone.Data.Id) { FailErrand(a, "no zone beyond the border there"); return; }
			int zid = to["zone"].AsInt32();
			Watch?.Event(a, "ZONE_CROSS", $"walks into zone {zid} on its way to {a.ErrandName}", 0);
			a.NextErrandCheck = 0;
			ClearErrand(a);
			a.Vel = Vector3.Zero;
			a.State = St.Wait;
			a.Timer = 2f;
			_crossings.Add((a, zid, to["pos"].AsVector3()));       // handed over after the movement loop
			return;
		}
		if (Flat(here, a.ErrandLocal) > 12f) { FailErrand(a, $"couldn't get within reach ({Flat(here, a.ErrandLocal):0} m)"); return; }
		string done = a.Zone.Combat?.Call("bot_errand_do", a.Foe, a.ErrandKind, a.ErrandWant).AsString() ?? "";
		if (done == "") { FailErrand(a, "nothing could be done there"); return; }
		a.Note(done);
		string tag = a.ErrandKind switch { "promote" => "PROMOTE", "train" => "TRAIN", "sell" => "SELL", _ => "ARROWS" };
		Watch?.Event(a, tag, done, 0);
		if (a.ErrandKind == "promote")
		{
			a.Record["class_name"] = a.Foe.Get(SSheet).AsGodotObject().Call("class_title");
			a.SwingSecs = Melee.Call("swing_seconds", Sheet(a), Melee.Call("weapon", Sheet(a))).AsSingle();
		}
		ClearErrand(a);
		a.NextErrandCheck = _time + 3.0;
		a.State = St.Pick;
	}

	// ---------------------------------------------------------------- the road ahead (old server: route threat awareness)

	// Every 2 s while walking: the first aggressive monster whose aggro reaches the next ~30 m of its path. An even
	// fight is pulled on its own terms; a strong one or a pack is stepped around (twice at most); then a manageable one is
	// pulled anyway and a hopeless one ends this trip (a new goal).
	bool RouteThreats(BotAgent a, Vector3 pos)
	{
		a.NextRouteScan = _time + 2.0;
		var pts = new List<Vector3>();
		float run = 0f;
		var last = pos;
		for (int i = a.PathI; i < a.Path.Length && run < 30f; i++)
		{
			run += last.DistanceTo(a.Path[i]);
			last = a.Path[i];
			pts.Add(last);
		}
		if (pts.Count == 0 || a.Zone.Combat == null) return false;
		var r = a.Zone.Combat.Call("bot_route_threat", a.Foe, pts.ToArray(), a.RouteAvoids).AsGodotDictionary();
		if (r.Count == 0) return false;
		var st = r["st"].AsGodotObject();
		string act = (string)r["act"];
		string name = (string)st.Get("spawn").AsGodotDictionary()["name"];
		if (act == "pull")
		{
			Watch?.Event(a, "ROUTE_THREAT", $"pulls {name} off the road", 30, ("act", act));
			StartFight(a, st, "clears the road of");
			return true;
		}
		if (act == "avoid")
		{
			var side = a.Zone.ClosestPoint(r["side"].AsVector3());
			a.RouteAvoids++;
			Watch?.Event(a, "ROUTE_THREAT", $"steps around {name}", 30, ("act", act));
			var rest = new List<Vector3> { side };
			for (int i = Math.Min(a.Path.Length - 1, a.PathI + pts.Count); i < a.Path.Length; i++) rest.Add(a.Path[i]);
			a.Path = rest.ToArray();
			a.PathI = 0;
			return false;
		}
		Watch?.Event(a, "ROUTE_THREAT", $"{name} blocks the way and is too strong: gives up this trip", 30, ("act", act));
		if (a.ErrandKind != "") FailErrand(a, $"{name} blocks the way");
		else AbandonCamp(a, $"the way is blocked by {name}", 1800);
		a.Vel = Vector3.Zero;
		return true;
	}

	// ---------------------------------------------------------------- paths

	void Request(BotAgent a)
	{
		a.State = St.WaitPath;
		Set(a, "THINKING", "");
		_queue.Enqueue(a);
	}

	void Dispatch(BotAgent a)
	{
		_inFlight++;
		int id = a.Id;
		Rid map = a.Zone.Map;
		var from = a.Body.GlobalPosition;
		var to = a.Goal;
		WorkerThreadPool.AddTask(Callable.From(() =>
		{
			var q = new NavigationPathQueryParameters3D { Map = map, StartPosition = from, TargetPosition = to };
			var r = new NavigationPathQueryResult3D();
			NavigationServer3D.QueryPath(q, r);
			var path = r.Path;
			lock (_lock) _results.Add((id, path));
		}));
	}

	void DrainResults()
	{
		List<(int id, Vector3[] path)> done;
		lock (_lock)
		{
			done = _results;
			_results = new();
		}
		foreach (var (rid, path) in done)
		{
			_inFlight--;
			Paths++;
			if (rid < 0)
			{
				// a chase path: used while it still hunts that monster
				if (_byId.TryGetValue(-rid - 1, out var c) && (c.State == St.Hunt || c.State == St.Follow) && path.Length > 0)
				{
					c.Path = path;
					c.PathI = path.Length > 1 ? 1 : 0;
				}
				continue;
			}
			if (!_byId.TryGetValue(rid, out var a) || a.State != St.WaitPath) continue;   // left meanwhile / fighting now
			if (path.Length == 0)
			{
				Fails++;
				a.Note("no path - picking another goal");
				Watch?.Event(a, "ROUTE_FAIL", $"no path to {a.Goal.Round()} ({a.Goal_})");
				if (a.ErrandKind != "")
				{
					a.Foe?.Call("block_errand", a.ErrandKind, 1800);
					ClearErrand(a);
				}
				else if (a.CampIdx >= 0) a.BadCamps[a.CampIdx] = _time + 1800;
				a.State = St.Pick;
				continue;
			}
			a.Path = path;
			a.PathI = path.Length > 1 ? 1 : 0;
			a.State = St.Travel;
			Set(a, "TRAVEL", "");
			a.CheckT = 0f;
			a.CheckPos = a.Body.GlobalPosition;
		}
	}

	// ---------------------------------------------------------------- movement (player.gd _client_move)

	void Move(BotAgent a, float delta)
	{
		var pos = a.Body.GlobalPosition;
		var target = a.Path[a.PathI];
		var flat = new Vector3(target.X - pos.X, 0f, target.Z - pos.Z);
		if (flat.Length() < WaypointReached)
		{
			a.PathI++;
			if (a.PathI >= a.Path.Length)
			{
				a.Vel = Vector3.Zero;
				Arrived++;
				a.Repaths = 0;
				if (a.ErrandKind != "")                   // at its errand's NPC (or the zone border on the way)
				{
					ArriveErrand(a);
					return;
				}
				a.ResumeTravel = false;
				a.State = St.Hunt;                         // at the camp: look for a monster of its level
				a.Prey = null;
				a.HuntTries = 0;
				Set(a, "HUNTING", "");
				return;
			}
			target = a.Path[a.PathI];
			flat = new Vector3(target.X - pos.X, 0f, target.Z - pos.Z);
		}
		if (!a.Companion && _time >= a.NextRouteScan && RouteThreats(a, pos))
			return;
		a.Vel = flat.Normalized() * RunSpeed;
		a.Face = Mathf.RadToDeg(Mathf.Atan2(-a.Vel.X, -a.Vel.Z));
		if (a.Grounded) a.Vy = 0f; else a.Vy -= Gravity * delta;
		ulong tt0 = Time.GetTicksUsec();
		a.Zone.Touch(pos);
		Prof["move: touch"] = (Prof.TryGetValue("move: touch", out var tv) ? tv : 0) + Time.GetTicksUsec() - tt0;
		ClientMove(a, delta);
	}

	void ClientMove(BotAgent a, float delta)
	{
		ulong cm0 = Time.GetTicksUsec();
		ClientMove2(a, delta);
		Prof["move: clientmove"] = (Prof.TryGetValue("move: clientmove", out var v) ? v : 0) + Time.GetTicksUsec() - cm0;
		Prof["move: clientmove n"] = (Prof.TryGetValue("move: clientmove n", out var n) ? n : 0) + 1;
	}

	void ClientMove2(BotAgent a, float delta)
	{
		var body = a.Body;
		var z = a.Zone;
		var space = z.Space;
		var pos = body.GlobalPosition;
		float feetBefore = pos.Y, vy = a.Vy, y = feetBefore + vy * delta;
		var step = new Vector3(a.Vel.X, 0f, a.Vel.Z) * delta;
		float floorY = FloorBelow(z, space, pos.X + step.X, y, pos.Z + step.Z, feetBefore);
		bool lifted = false;
		if (floorY > y) { y = floorY; lifted = true; }
		if (step.Length() > 0.0001f && a.Grounded)
		{
			var lead = pos + step.Normalized() * (StepLead + 0.02f);
			float leadY = FloorBelow(z, space, lead.X, y, lead.Z, feetBefore);
			if (leadY > y && leadY - y <= ColliderLift) { y = leadY; lifted = true; }
		}
		Vector3 p2;
		bool open = !z.Data.NearWall(pos.X, pos.Z) && !z.Data.NearWall(pos.X + step.X, pos.Z + step.Z);
		if (open)
			p2 = new Vector3(pos.X + step.X, y, pos.Z + step.Z);    // open ground: nothing to slide along
		else
		{
			body.GlobalPosition = new Vector3(pos.X, y, pos.Z);
			body.Velocity = new Vector3(a.Vel.X, 0f, a.Vel.Z);
			Prof["move: slide n"] = (Prof.TryGetValue("move: slide n", out var sn) ? sn : 0) + 1;
			body.MoveAndSlide();
			p2 = body.GlobalPosition;
			p2.Y = y;
		}
		// the floor where it ended up - on open ground at the same spot and height as the first pick (nothing lifted it),
		// that pick's answer is this one's (the same ray): one ray fewer a step
		if (!(open && !lifted)) floorY = FloorBelow(z, space, p2.X, p2.Y, p2.Z, feetBefore);
		if ((a.Grounded && vy <= 0f && p2.Y - floorY <= FallHeight + 0.025f) || (p2.Y - floorY <= FloorSnap && vy <= 0f))
		{
			p2.Y = floorY;
			a.Grounded = true;
			a.Vy = 0f;
		}
		else a.Grounded = false;
		body.GlobalPosition = p2;                                   // one write a step (each pushes the body to physics)
		if (!z.Data.City && p2.Y < z.Data.Grid(p2.X, p2.Z) - 2f && !a.Fell)
		{
			a.Fell = true;                                       // diagnostics: below the ground grid (a fall through)
			string msg = $"FELL below the ground at {p2.Round()} (grid {z.Data.Grid(p2.X, p2.Z):0.0}, from {pos.Round()}, feet {feetBefore:0.0}, vy {vy:0.0}, grounded {a.Grounded}, wall near {z.Data.NearWall(pos.X, pos.Z)})";
			a.Note(msg);
			FellAt?.Invoke(a, msg);
		}
	}

	public Action<BotAgent, string> FellAt;
	public static bool VerifyFloor;                  // tests: compare the C# floor pick with the physics ray
	public int VerifyN, VerifyPlus, VerifyMinus;
	int _verifyLeft = 200000;
	static bool Same(float a, float b) => (float.IsNegativeInfinity(a) && float.IsNegativeInfinity(b)) || Math.Abs(a - b) < 0.02f;

	float FloorBelow(ZoneWorld z, PhysicsDirectSpaceState3D space, float x, float y, float zz, float feetBefore)
	{
		float start = y + Math.Max(PickLift, feetBefore - y);
		float best = float.NegativeInfinity;
		if (!z.Data.City)
		{
			float t = z.Data.Grid(x, zz);
			if (t <= start) best = t;
			if (!z.Data.NearFloor(x, zz)) return best;               // no fixture floor here: the grid is the floor
		}
		Prof["move: rays n"] = (Prof.TryGetValue("move: rays n", out var rn) ? rn : 0) + 1;
		float pick = z.Data.FloorPick(x, zz, start, z.Data.UpSign);
		if (VerifyFloor && _verifyLeft > 0)
		{
			// tests (--verify-floor): the C# pick against the physics ray it replaces, for both windings
			_verifyLeft--;
			_ray.From = new Vector3(x, start, zz);
			_ray.To = new Vector3(x, start - 500f, zz);
			var hit = space.IntersectRay(_ray);
			float hy = hit.Count > 0 ? hit["position"].AsVector3().Y : float.NegativeInfinity;
			float p1 = z.Data.FloorPick(x, zz, start, 1), p2 = z.Data.FloorPick(x, zz, start, -1);
			VerifyN++;
			if (Same(p1, hy)) VerifyPlus++;
			if (Same(p2, hy)) VerifyMinus++;
		}
		if (pick > best) best = pick;
		return best;
	}
}
