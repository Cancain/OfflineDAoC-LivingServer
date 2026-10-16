// A zone as the bots need it (bot plan phase 3), read from content/zones/zoneNNN/world (tools/export_world_collision.gd
// - the collision exactly as the game builds it) and the zone's height grid: floors, walls, the solid buildings'
// floors for navigation, spots, monster camps, exits, and the open-ground masks (4 m cells: no fixture floor near -> the
// floor is the height grid; no wall near -> nothing to slide along - the open-ground shortcut, owner's choice).
using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace MMOEngine;

public sealed class ZoneData
{
	public const float MaskM = 4f;
	public const float ChunkM = 64f;           // collision blocks: small enough to build without a hitch

	public int Id;
	public string Name = "";
	public float SizeM;
	public bool City;
	public float[] Heights = Array.Empty<float>();
	public int HSize;
	public float Cell;
	public Vector3[] Spots = Array.Empty<Vector3>();
	public Vector3[] Camps = Array.Empty<Vector3>();
	public int[] CampLevels = Array.Empty<int>();
	public float[] CampAggro = Array.Empty<float>();
	public float[] Floor = Array.Empty<float>(), Walls = Array.Empty<float>(), NavFloor = Array.Empty<float>();
	public int MaskN;
	public byte[] FloorMask = Array.Empty<byte>(), WallMask = Array.Empty<byte>();
	public int ChunkN;
	public List<int>[] FloorChunks, WallChunks;    // triangle indices per 128 m cell (by the first vertex)

	public static string Dir(int id) => $"res://content/zones/zone{id:000}";

	public static bool Exists(int id) => FileAccess.FileExists(Dir(id) + "/world/meta.json");

	public static ZoneData Load(int id)
	{
		string dir = Dir(id);
		var meta = Json.ParseString(FileAccess.GetFileAsString(dir + "/world/meta.json")).AsGodotDictionary();
		var z = new ZoneData
		{
			Id = id, Name = (string)meta["name"], SizeM = (float)(double)meta["size_m"], City = (bool)meta["city"],
			HSize = (int)(double)meta["hsize"], Cell = (float)(double)meta["cell"],
		};
		if (!z.City) z.Heights = Floats(dir + "/" + (string)meta["heights"]);
		z.Floor = Floats(dir + "/world/floor.f32");
		z.Walls = Floats(dir + "/world/walls.f32");
		z.NavFloor = Floats(dir + "/world/navfloor.f32");
		var spots = new List<Vector3>();
		foreach (var s in meta["spots"].AsGodotArray())
			spots.Add(Vec(s.AsGodotDictionary()["pos"].AsGodotArray()));
		z.Spots = spots.ToArray();
		var camps = new List<Vector3>();
		var lv = new List<int>();
		var ag = new List<float>();
		foreach (var c in meta["camps"].AsGodotArray())
		{
			var d = c.AsGodotDictionary();
			camps.Add(Vec(d["pos"].AsGodotArray()));
			lv.Add((int)(double)d["level"]);
			ag.Add((bool)d["aggressive"] ? (float)(double)d["aggro"] : 0f);
		}
		z.Camps = camps.ToArray();
		z.CampLevels = lv.ToArray();
		z.CampAggro = ag.ToArray();
		z.MaskN = (int)Math.Ceiling(z.SizeM / MaskM);
		z.FloorMask = Mask(z.Floor, z.MaskN);
		z.WallMask = Mask(z.Walls, z.MaskN);
		z.ChunkN = (int)Math.Ceiling(z.SizeM / ChunkM);
		z.FloorChunks = Bin(z.Floor, z.ChunkN);
		z.WallChunks = Bin(z.Walls, z.ChunkN);
		return z;
	}

	static Vector3 Vec(Godot.Collections.Array a) => new((float)(double)a[0], (float)(double)a[1], (float)(double)a[2]);

	static float[] Floats(string path)
	{
		if (!FileAccess.FileExists(path)) return Array.Empty<float>();
		return MemoryMarshal.Cast<byte, float>(FileAccess.GetFileAsBytes(path)).ToArray();
	}

	static byte[] Mask(float[] t, int n)
	{
		var m = new byte[n * n];
		for (int k = 0; k + 8 < t.Length; k += 9)
		{
			float x0 = Math.Min(t[k], Math.Min(t[k + 3], t[k + 6])) - 1f, x1 = Math.Max(t[k], Math.Max(t[k + 3], t[k + 6])) + 1f;
			float z0 = Math.Min(t[k + 2], Math.Min(t[k + 5], t[k + 8])) - 1f, z1 = Math.Max(t[k + 2], Math.Max(t[k + 5], t[k + 8])) + 1f;
			int a0 = Math.Clamp((int)(x0 / MaskM), 0, n - 1), a1 = Math.Clamp((int)(x1 / MaskM), 0, n - 1);
			int b0 = Math.Clamp((int)(z0 / MaskM), 0, n - 1), b1 = Math.Clamp((int)(z1 / MaskM), 0, n - 1);
			for (int b = b0; b <= b1; b++)
				for (int a = a0; a <= a1; a++)
					m[b * n + a] = 1;
		}
		return m;
	}

	static List<int>[] Bin(float[] t, int n)
	{
		var bins = new List<int>[n * n];
		for (int k = 0, tri = 0; k + 8 < t.Length; k += 9, tri++)
		{
			int a = Math.Clamp((int)(t[k] / ChunkM), 0, n - 1), b = Math.Clamp((int)(t[k + 2] / ChunkM), 0, n - 1);
			(bins[b * n + a] ??= new List<int>()).Add(tri);
		}
		return bins;
	}

	public bool NearFloor(float x, float z) => FloorMask.Length > 0
		&& FloorMask[Math.Clamp((int)(z / MaskM), 0, MaskN - 1) * MaskN + Math.Clamp((int)(x / MaskM), 0, MaskN - 1)] != 0;

	public bool NearWall(float x, float z) => WallMask.Length > 0
		&& WallMask[Math.Clamp((int)(z / MaskM), 0, MaskN - 1) * MaskN + Math.Clamp((int)(x / MaskM), 0, MaskN - 1)] != 0;

	// The ground grid's height (bilinear) - the game's floor pick outside cities (ZoneLoader._grid_height).
	public float Grid(float x, float z)
	{
		if (Heights.Length == 0) return float.NegativeInfinity;
		int hs = HSize;
		float gx = Math.Clamp(x / Cell, 0f, hs - 1.001f), gz = Math.Clamp(z / Cell, 0f, hs - 1.001f);
		int ix = (int)gx, iz = (int)gz;
		float fx = gx - ix, fz = gz - iz;
		float top = Mathf.Lerp(Heights[iz * hs + ix], Heights[iz * hs + ix + 1], fx);
		float bottom = Mathf.Lerp(Heights[(iz + 1) * hs + ix], Heights[(iz + 1) * hs + ix + 1], fx);
		return Mathf.Lerp(top, bottom, fz);
	}

	// ---------------------------------------------------------------- the floor pick without the physics engine
	// The host's bots ask "the floor under this point" ~1,000 times a tick near buildings; a physics ray each (into the
	// engine and back, a result dictionary every time) cost ~5 ms a tick at 1,500 bots. The same floor triangles the
	// physics blocks are built from are kept here in 4 m cells per 64 m block (built on first use), and the pick is a
	// small triangle test: the highest up-facing floor at or below `start`, within 500 m (the ray's length).
	const float FineM = 4f;
	const int FineN = 16;                         // cells per block side (64 / 4)
	readonly Dictionary<int, int[][]> _fine = new();
	public int UpSign = -1;                       // the winding the physics engine treats as facing up (--verify-floor: 199,996 of 200,000 picks matched its rays)

	int[][] FineCells(int cx, int cz)
	{
		int key = cz * ChunkN + cx;
		if (_fine.TryGetValue(key, out var have)) return have;
		var cells = new List<int>[FineN * FineN];
		float x0 = cx * ChunkM, z0 = cz * ChunkM;
		ulong t0 = Time.GetTicksUsec();
		long scanned = 0;
		for (int dz = -1; dz <= 1; dz++)
			for (int dx = -1; dx <= 1; dx++)
			{
				int bx = cx + dx, bz = cz + dz;
				if (bx < 0 || bz < 0 || bx >= ChunkN || bz >= ChunkN) continue;
				var list = FloorChunks[bz * ChunkN + bx];
				if (list == null) continue;
				foreach (int tri in list)
				{
					scanned++;
					int k = tri * 9;
					float minx = Math.Min(Floor[k], Math.Min(Floor[k + 3], Floor[k + 6])), maxx = Math.Max(Floor[k], Math.Max(Floor[k + 3], Floor[k + 6]));
					float minz = Math.Min(Floor[k + 2], Math.Min(Floor[k + 5], Floor[k + 8])), maxz = Math.Max(Floor[k + 2], Math.Max(Floor[k + 5], Floor[k + 8]));
					int i0 = (int)Math.Floor((minx - x0) / FineM), i1 = (int)Math.Floor((maxx - x0) / FineM);
					int j0 = (int)Math.Floor((minz - z0) / FineM), j1 = (int)Math.Floor((maxz - z0) / FineM);
					if (i1 < 0 || j1 < 0 || i0 >= FineN || j0 >= FineN) continue;
					i0 = Math.Max(i0, 0); j0 = Math.Max(j0, 0); i1 = Math.Min(i1, FineN - 1); j1 = Math.Min(j1, FineN - 1);
					for (int j = j0; j <= j1; j++)
						for (int i = i0; i <= i1; i++)
							(cells[j * FineN + i] ??= new List<int>()).Add(tri);
				}
			}
		var arr = new int[FineN * FineN][];
		long refs = 0;
		for (int c = 0; c < arr.Length; c++) { arr[c] = cells[c]?.ToArray() ?? Array.Empty<int>(); refs += arr[c].Length; }
		_fine[key] = arr;
		double ms = (Time.GetTicksUsec() - t0) / 1000.0;
		if (ms > 20) GD.Print($"[host] floor cells {Name} block {cx},{cz}: {scanned} triangles looked at, {refs} cell entries, {ms:0} ms");
		return arr;
	}

	public float FloorPick(float x, float z, float start, int upSign)
	{
		int cx = (int)Math.Floor(x / ChunkM), cz = (int)Math.Floor(z / ChunkM);
		if (cx < 0 || cz < 0 || cx >= ChunkN || cz >= ChunkN) return float.NegativeInfinity;
		var cells = FineCells(cx, cz);
		int i = Math.Clamp((int)((x - cx * ChunkM) / FineM), 0, FineN - 1), j = Math.Clamp((int)((z - cz * ChunkM) / FineM), 0, FineN - 1);
		float best = float.NegativeInfinity, low = start - 500f;
		var f = Floor;
		foreach (int tri in cells[j * FineN + i])
		{
			int k = tri * 9;
			float ax = f[k], ay = f[k + 1], az = f[k + 2], bx = f[k + 3], by = f[k + 4], bz = f[k + 5], qx = f[k + 6], qy = f[k + 7], qz = f[k + 8];
			float ny = (bz - az) * (qx - ax) - (bx - ax) * (qz - az);   // the face normal's y (by the winding)
			if (ny * upSign <= 0f) continue;                            // faces down / vertical: the ray passes it
			float d = (bz - qz) * (ax - qx) + (qx - bx) * (az - qz);
			if (Math.Abs(d) < 1e-9f) continue;
			float l1 = ((bz - qz) * (x - qx) + (qx - bx) * (z - qz)) / d;
			float l2 = ((qz - az) * (x - qx) + (ax - qx) * (z - qz)) / d;
			float l3 = 1f - l1 - l2;
			const float eps = -1e-5f;
			if (l1 < eps || l2 < eps || l3 < eps) continue;
			float h = l1 * ay + l2 * by + l3 * qy;
			if (h <= start && h >= low && h > best) best = h;
		}
		return best;
	}

	public Vector3[] ChunkFaces(float[] tris, List<int>[] bins, int cx, int cz)
	{
		var list = bins[cz * ChunkN + cx];
		if (list == null) return Array.Empty<Vector3>();
		var v = new Vector3[list.Count * 3];
		int o = 0;
		foreach (int tri in list)
		{
			int k = tri * 9;
			v[o++] = new Vector3(tris[k], tris[k + 1], tris[k + 2]);
			v[o++] = new Vector3(tris[k + 3], tris[k + 4], tris[k + 5]);
			v[o++] = new Vector3(tris[k + 6], tris[k + 7], tris[k + 8]);
		}
		return v;
	}
}
