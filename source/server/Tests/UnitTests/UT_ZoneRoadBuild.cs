using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Text.Json;
using System.Threading.Tasks;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Tool: proves the candidate zone road legs (tools/navmesh_splice/roadgraph.py) with the server's
    /// own Detour corridor check, each direction separately, and writes navmesh/roads.json
    /// (AutonomousZoneRoads) with each leg's walked length. Anchors left without a proven leg are dropped.
    /// Env: OFFLINE_DAOC_NAV_ROOT (folder with navmesh/ and lib/Detour.dll), OFFLINE_DAOC_ROADS_IN
    /// (candidates json), OFFLINE_DAOC_ROADS_OUT (roads.json to write).
    /// </summary>
    [TestFixture, Explicit("Zone road graph build tool"), NonParallelizable]
    public class UT_ZoneRoadBuild
    {
        [Test]
        public void BuildZoneRoads()
        {
            string root = Environment.GetEnvironmentVariable("OFFLINE_DAOC_NAV_ROOT");
            string input = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ROADS_IN");
            string output = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ROADS_OUT");
            Assume.That(root != null && input != null && output != null);
            string previous = Environment.CurrentDirectory;
            Environment.CurrentDirectory = root;
            var nav = PathfindingProvider.LocalPathfindingMgr;
            using JsonDocument candidates = JsonDocument.Parse(File.ReadAllText(input));
            int cell = candidates.RootElement.GetProperty("cell").GetInt32();
            var zonesOut = new SortedDictionary<int, object>();
            try
            {
                foreach (JsonProperty entry in candidates.RootElement.GetProperty("zones").EnumerateObject())
                {
                    var watch = System.Diagnostics.Stopwatch.StartNew();
                    JsonElement data = entry.Value;
                    ushort id = ushort.Parse(entry.Name);
                    var zone = new Zone(null, id, $"zone{id}", data.GetProperty("x").GetInt32(), data.GetProperty("y").GetInt32(),
                        data.GetProperty("w").GetInt32(), data.GetProperty("h").GetInt32(), id, false, 0, false, 0, 0, 0, 0, 0);
                    int[][] anchors = data.GetProperty("anchors").EnumerateArray()
                        .Select(a => a.EnumerateArray().Select(v => v.GetInt32()).ToArray()).ToArray();
                    int[][] pairs = data.GetProperty("edges").EnumerateArray()
                        .Select(e => e.EnumerateArray().Select(v => v.GetInt32()).ToArray()).ToArray();
                    Vector3 At(int i) => new(anchors[i][0], anchors[i][1], anchors[i][2]);
                    LocalPathfindingMgr.LoadNavMesh(zone);
                    var proven = new ConcurrentBag<(int From, int To, int Length)>();
                    try
                    {
                        Parallel.ForEach(pairs, new ParallelOptions { MaxDegreeOfParallelism = 6 }, pair =>
                        {
                            // The walked length, not the chord, is the leg's cost (UT_ZoneRoadWeights).
                            foreach ((int from, int to) in new[] { (pair[0], pair[1]), (pair[1], pair[0]) })
                            {
                                float walked = AutonomousZoneItinerary.CorridorLength(nav, zone, At(from), At(to));
                                if (!float.IsNaN(walked))
                                    proven.Add((from, to, (int)MathF.Ceiling(Math.Max(walked, Vector3.Distance(At(from), At(to))))));
                            }
                        });
                    }
                    finally { LocalPathfindingMgr.UnloadNavMesh(zone); }
                    // Keep anchors that have a proven leg; renumber them in their original order.
                    var used = proven.SelectMany(p => new[] { p.From, p.To }).Distinct().OrderBy(i => i).ToArray();
                    var index = used.Select((anchor, n) => (anchor, n)).ToDictionary(x => x.anchor, x => x.n);
                    if (used.Length > 0)
                        zonesOut[id] = new
                        {
                            anchors = used.Select(i => anchors[i]).ToArray(),
                            edges = proven.Select(p => new[] { index[p.From], index[p.To], p.Length }).OrderBy(e => e[0]).ThenBy(e => e[1]).ToArray()
                        };
                    TestContext.Progress.WriteLine($"zone {id}: {used.Length}/{anchors.Length} anchors, {proven.Count}/{pairs.Length * 2} legs proven, {watch.Elapsed.TotalSeconds:F0}s");
                }
            }
            finally { Environment.CurrentDirectory = previous; }
            File.WriteAllText(output, JsonSerializer.Serialize(new
            {
                version = 1,
                cell,
                zones = zonesOut.ToDictionary(z => z.Key.ToString(), z => z.Value)
            }));
        }
    }
}
