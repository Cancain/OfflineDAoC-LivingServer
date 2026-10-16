// A zone the bots live in (bot plan phase 3). In the world host: its own physics space (a SubViewport with its own
// World3D) with the floor and wall layers built in 128 m blocks only where bots are (released when none is near for a
// while), and its navigation map. In the game (zone handover): the game's own zone physics, plus the navigation map.
// Navigation is baked once per zone from the ground grid, the walls and the solid buildings' floors (never every prop
// surface - Godot's map can't join that many islands, phase 0), in 256 m tiles on a worker thread, and cached in the
// user folder (world/nav).
using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace MMOEngine;

public sealed class ZoneWorld
{
	public const uint LayerWall = 1;
	public const uint LayerFloor = 2;
	const float TileM = 256f;
	const float NavCell = 0.4f;
	const float NavCellH = 0.15f;               // fine enough for the player's step-up (0.62 m: 4 cells)
	const double ChunkKeep = 60.0;              // seconds a block stays after the last bot left it

	public readonly ZoneData Data;
	public readonly World3D World;
	public readonly Rid Map;
	public readonly Node BodyParent;             // where bots' bodies go
	public Node3D Npcs;                          // the zone's monsters and people (NpcManager - the game's own simulation)
	public GodotObject Combat;                   // the zone's fights (Combat: monsters and gamebots, the player's rules)
	public volatile bool NavReady;
	public string NavStatus = "not started";
	readonly bool _ownPhysics;
	readonly Dictionary<Vector2I, (StaticBody3D floor, StaticBody3D walls, double lastUsed)> _chunks = new();
	double _clock;

	ZoneWorld(ZoneData d, World3D world, Node bodyParent, bool ownPhysics)
	{
		Data = d;
		World = world;
		Map = world.NavigationMap;
		BodyParent = bodyParent;
		_ownPhysics = ownPhysics;
		NavigationServer3D.MapSetCellSize(Map, NavCell);
		NavigationServer3D.MapSetCellHeight(Map, NavCellH);
		NavigationServer3D.MapSetEdgeConnectionMargin(Map, 0.6f);
		NavigationServer3D.MapSetActive(Map, true);
	}

	// The world host: a physics space of its own.
	public static ZoneWorld ForHost(Node parent, ZoneData d)
	{
		var vp = new SubViewport
		{
			OwnWorld3D = true, RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled, Size = new Vector2I(2, 2),
			Name = $"Zone{d.Id:000}",
		};
		parent.AddChild(vp);
		var zw = new ZoneWorld(d, vp.FindWorld3D(), vp, true);
		// the monsters: the game's own NpcManager on a graphics-free zone (HeadlessZone) in this physics world
		string dir = ZoneData.Dir(d.Id);
		var hz = GD.Load<GDScript>("res://game/world_host/headless_zone.gd").New().As<Node3D>();
		vp.AddChild(hz);
		hz.Call("load_headless", dir);
		var nm = GD.Load<GDScript>("res://game/npcs/npc_manager.gd").New().As<Node3D>();
		vp.AddChild(nm);
		nm.Call("setup", dir, hz, new Variant());
		zw.Npcs = nm;
		// the fights: the game's own Combat with no player - monsters chasing and swinging at bots, bots' blows
		var combat = GD.Load<GDScript>("res://game/combat/combat.gd").New().As<Node>();
		combat.Name = "Combat";
		vp.AddChild(combat);
		combat.Call("setup_host", nm);
		zw.Combat = combat;
		return zw;
	}

	// The game: the zone the player is in (its physics already built by ZoneLoader).
	public static ZoneWorld ForGame(Node zoneRoot, ZoneData d) => new(d, ((Node3D)zoneRoot).GetWorld3D(), zoneRoot, false);

	public PhysicsDirectSpaceState3D Space => World.DirectSpaceState;

	// The floor / wall blocks around a position (host only): the 3 x 3 blocks of 128 m around it.
	public void Touch(Vector3 p)
	{
		if (!_ownPhysics) return;
		int cx = (int)(p.X / ZoneData.ChunkM), cz = (int)(p.Z / ZoneData.ChunkM);
		for (int dz = -1; dz <= 1; dz++)
			for (int dx = -1; dx <= 1; dx++)
			{
				int x = cx + dx, z = cz + dz;
				if (x < 0 || z < 0 || x >= Data.ChunkN || z >= Data.ChunkN) continue;
				var key = new Vector2I(x, z);
				if (_chunks.TryGetValue(key, out var c)) { _chunks[key] = (c.floor, c.walls, _clock); continue; }
				if (_queued.Add(key)) _queue.Enqueue(key);            // built a couple per update (BuildQueued)
			}
	}

	readonly Queue<Vector2I> _queue = new();
	readonly HashSet<Vector2I> _queued = new();

	// At most two blocks built per update (a town block is tens of thousands of triangles: building many at once
	// stalled the host up to 0.6 s); requested a ring ahead of each bot, so they're there before it arrives.
	void BuildQueued()
	{
		for (int n = 0; n < 2 && _queue.Count > 0; n++)
		{
			var key = _queue.Dequeue();
			_queued.Remove(key);
			if (_chunks.ContainsKey(key)) continue;
			_chunks[key] = (Body(Data.ChunkFaces(Data.Floor, Data.FloorChunks, key.X, key.Y), LayerFloor, true),
				Body(Data.ChunkFaces(Data.Walls, Data.WallChunks, key.X, key.Y), LayerWall, false), _clock);
		}
	}

	// Blocks no bot has touched for a minute are released (memory stays with where the bots are).
	public void Tick(double delta)
	{
		_clock += delta;
		if (!_ownPhysics) return;
		BuildQueued();
		List<Vector2I> old = null;
		foreach (var kv in _chunks)
			if (_clock - kv.Value.lastUsed > ChunkKeep) (old ??= new()).Add(kv.Key);
		if (old == null) return;
		foreach (var k in old)
		{
			_chunks[k].floor?.QueueFree();
			_chunks[k].walls?.QueueFree();
			_chunks.Remove(k);
		}
	}

	public int Chunks => _chunks.Count;

	// A bot entering the zone: the blocks around it are built at once (not queued).
	public void TouchNow(Vector3 p)
	{
		Touch(p);
		while (_queue.Count > 0) BuildQueued();
	}

	StaticBody3D Body(Vector3[] faces, uint layer, bool backFaces)
	{
		if (faces.Length == 0) return null;
		var body = new StaticBody3D { CollisionLayer = layer, CollisionMask = 0 };
		var shape = new ConcavePolygonShape3D { BackfaceCollision = backFaces };
		shape.SetFaces(faces);
		body.AddChild(new CollisionShape3D { Shape = shape });
		BodyParent.AddChild(body);
		return body;
	}

	// ---------------------------------------------------------------- navigation

	// The zone's navigation tiles leave the world's map (a zone handover in the game: the next zone's tiles go on the same
	// map, and the scene moved - the old tiles would lie at the wrong place). A build still running stops at its next tile.
	public void FreeNav()
	{
		_navCancelled = true;
		lock (_regions)
		{
			foreach (var r in _regions) NavigationServer3D.FreeRid(r);
			_regions.Clear();
			_tilesN = 0;
			_tileRegion = Array.Empty<Rid>();
		}
		NavReady = false;
	}

	readonly List<Rid> _regions = new();
	volatile bool _navCancelled;
	Rid[] _tileRegion = Array.Empty<Rid>();          // tile (tz * n + tx) -> its navigation region
	int _tilesN;

	// The walkable point nearest p, from the navigation tiles around it only. The whole map's query walked every tile of
	// the zone - ~1-3 ms each, 5.4 ms a host tick at 1,500 bots. Falls back to the whole map when nothing is near.
	public Vector3 ClosestPoint(Vector3 p)
	{
		int n = _tilesN;
		if (n > 0)
		{
			int cx = (int)Math.Floor(p.X / TileM), cz = (int)Math.Floor(p.Z / TileM);
			var best = Vector3.Zero;
			float bd = float.MaxValue;
			for (int dz = -1; dz <= 1; dz++)
				for (int dx = -1; dx <= 1; dx++)
				{
					int tx = cx + dx, tz = cz + dz;
					if (tx < 0 || tz < 0 || tx >= n || tz >= n) continue;
					var r = _tileRegion[tz * n + tx];
					if (!r.IsValid) continue;
					var c = NavigationServer3D.RegionGetClosestPoint(r, p);
					if (c == Vector3.Zero) continue;                   // (an empty tile)
					float d = c.DistanceSquaredTo(p);
					if (d < bd) { bd = d; best = c; }
				}
			if (bd < float.MaxValue) return best;
		}
		return NavigationServer3D.MapGetClosestPoint(Map, p);
	}

	static readonly System.Threading.SemaphoreSlim BakeSlots = new(2, 2);   // navmesh tiles baking at once, all zones

	public void StartNav(string cacheDir)
	{
		if (NavStatus != "not started") return;
		NavStatus = "loading";
		DirAccess.MakeDirRecursiveAbsolute(cacheDir);
		Task.Run(() => BuildNav(cacheDir));
	}

	void BuildNav(string cacheDir)
	{
		try
		{
			ulong t0 = Time.GetTicksMsec();
			int n = (int)Math.Ceiling(Data.SizeM / TileM);
			var tiles = new Rid[n * n];
			List<Vector3>[] bins = null;
			int baked = 0;
			for (int tz = 0; tz < n; tz++)
				for (int tx = 0; tx < n; tx++)
				{
					// the bake settings are in the name: a changed rule (cell size, step-up...) re-bakes instead of reusing;
					// so are the source's wall / floor counts: re-exported collision (the tree boxes, 2026-10-11) re-bakes too
					string path = $"{cacheDir}/zone{Data.Id:000}_{SettingsTag}_w{Data.Walls.Length / 9}f{Data.NavFloor.Length / 9}_{tx}_{tz}.res";
					NavigationMesh nm = FileAccess.FileExists(path) ? ResourceLoader.Load<NavigationMesh>(path) : null;
					if (nm == null)
					{
						bins ??= TileSources(n);
						nm = Settings();
						float border = NavCell * 12f;
						nm.FilterBakingAabb = new Aabb(new Vector3(tx * TileM - border, -100f, tz * TileM - border),
							new Vector3(TileM + border * 2f, 1150f, TileM + border * 2f));   // Recast: 13-bit spans (8,191 x 0.15 m)
						nm.BorderSize = border;
						var src = new NavigationMeshSourceGeometryData3D();
						src.AddFaces(bins[tz * n + tx].ToArray(), Transform3D.Identity);
						// in the background: the blocking bake held the navigation server's lock the main loop needs every
						// physics tick, and the whole host waited for every tile of the zone (minutes - owner 2026-10-11);
						// two tiles at a time across all zones (every zone baking at once took 8 of 12 threads off the
						// game - owner's walk 2026-10-11)
						while (!BakeSlots.Wait(250))
							if (_navCancelled) return;
						try
						{
							using var done = new System.Threading.ManualResetEventSlim(false);
							NavigationServer3D.BakeFromSourceGeometryDataAsync(nm, src, Callable.From(() => done.Set()));
							while (!done.Wait(250))
								if (_navCancelled) return;
						}
						finally { BakeSlots.Release(); }
						ResourceSaver.Save(nm, path);
						baked++;
					}
					if (_navCancelled) return;
					var region = NavigationServer3D.RegionCreate();
					NavigationServer3D.RegionSetMap(region, Map);
					NavigationServer3D.RegionSetNavigationMesh(region, nm);
					lock (_regions)
					{
						if (_navCancelled) { NavigationServer3D.FreeRid(region); return; }
						_regions.Add(region);
						tiles[tz * n + tx] = region;
					}
				}
			_tileRegion = tiles;
			_tilesN = n;
			NavStatus = $"tiles ready ({baked} baked now) in {(Time.GetTicksMsec() - t0) / 1000.0:0.0} s, joining";
			// the map joins its tiles in the background: ready once most of 20 points spread over the zone (camps and
			// spots) find walkable ground close by - one point found early gave paths to the edge of the part joined
			// so far (bots walking to the tile edges, phase 3)
			var probes = new List<Vector3>(Data.Spots);
			for (int i = 0; i < Data.Camps.Length && probes.Count < 20; i += Math.Max(1, Data.Camps.Length / 16)) probes.Add(Data.Camps[i]);
			for (int tries = 0; tries < 1200; tries++)
			{
				if (_navCancelled) return;
				int ok = 0;
				foreach (var p in probes)
				{
					var c = NavigationServer3D.MapGetClosestPoint(Map, p);
					if (c != Vector3.Zero && new Vector2(c.X - p.X, c.Z - p.Z).Length() < 10f) ok++;
				}
				if (probes.Count == 0 || ok >= probes.Count * 0.8f) break;
				System.Threading.Thread.Sleep(100);
			}
			// ...and the map has stopped changing (big tiles keep joining after the first points answer - Domnann)
			for (int tries = 0; tries < 60; tries++)
			{
				if (_navCancelled) return;
				var it = NavigationServer3D.MapGetIterationId(Map);
				System.Threading.Thread.Sleep(2000);
				if (NavigationServer3D.MapGetIterationId(Map) == it) break;
			}
			NavStatus = $"ready in {(Time.GetTicksMsec() - t0) / 1000.0:0.0} s ({baked} tiles baked now)";
			NavReady = true;
		}
		catch (Exception e)
		{
			NavStatus = "failed: " + e.Message;
		}
	}

	static string SettingsTag => $"c{NavCell * 100:0}h{NavCellH * 100:0}s{BotSim.ColliderLift * 100:0}";

	static NavigationMesh Settings() => new()
	{
		CellSize = NavCell, CellHeight = NavCellH, AgentHeight = 1.8f, AgentRadius = 0.3f, AgentMaxClimb = BotSim.ColliderLift,   // steps a player (and a bot) can really take
		AgentMaxSlope = 60f, RegionMinSize = 4f, RegionMergeSize = 20f, EdgeMaxError = 2f, DetailSampleDistance = 8f,
	};

	// Each tile's source geometry: the ground grid (outside cities), the walls and the solid buildings' floors whose
	// bounds touch the tile (plus its border).
	List<Vector3>[] TileSources(int n)
	{
		var bins = new List<Vector3>[n * n];
		for (int i = 0; i < bins.Length; i++) bins[i] = new List<Vector3>();
		const float pad = 4f;
		void AddTri(Vector3 a, Vector3 b, Vector3 c)
		{
			int x0 = Math.Clamp((int)((Math.Min(a.X, Math.Min(b.X, c.X)) - pad) / TileM), 0, n - 1);
			int x1 = Math.Clamp((int)((Math.Max(a.X, Math.Max(b.X, c.X)) + pad) / TileM), 0, n - 1);
			int z0 = Math.Clamp((int)((Math.Min(a.Z, Math.Min(b.Z, c.Z)) - pad) / TileM), 0, n - 1);
			int z1 = Math.Clamp((int)((Math.Max(a.Z, Math.Max(b.Z, c.Z)) + pad) / TileM), 0, n - 1);
			for (int z = z0; z <= z1; z++)
				for (int x = x0; x <= x1; x++)
				{
					var l = bins[z * n + x];
					l.Add(a); l.Add(b); l.Add(c);
				}
		}
		if (!Data.City)
		{
			int hs = Data.HSize;
			float cell = Data.Cell;
			var h = Data.Heights;
			for (int j = 0; j < hs - 1; j++)
				for (int i = 0; i < hs - 1; i++)
				{
					var p00 = new Vector3(i * cell, h[j * hs + i], j * cell);
					var p10 = new Vector3((i + 1) * cell, h[j * hs + i + 1], j * cell);
					var p01 = new Vector3(i * cell, h[(j + 1) * hs + i], (j + 1) * cell);
					var p11 = new Vector3((i + 1) * cell, h[(j + 1) * hs + i + 1], (j + 1) * cell);
					AddTri(p00, p10, p01);                        // the game's terrain winding (ZoneLoader)
					AddTri(p10, p11, p01);
				}
		}
		foreach (var t in new[] { Data.Walls, Data.NavFloor })
			for (int k = 0; k + 8 < t.Length; k += 9)
				AddTri(new Vector3(t[k], t[k + 1], t[k + 2]), new Vector3(t[k + 3], t[k + 4], t[k + 5]),
					new Vector3(t[k + 6], t[k + 7], t[k + 8]));
		return bins;
	}
}
