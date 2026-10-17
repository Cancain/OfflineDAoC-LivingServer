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
    /// Tool: adds each proven leg's walked length (AutonomousZoneItinerary.CorridorLength, the same Detour corridor the
    /// leg was proven with) to an existing navmesh/roads.json, as [from, to, length]. Anchors and legs are unchanged.
    /// The road search charged a leg its chord: two Sheeroe Hills anchors across a ravine, 3,842 apart, take 37,479 to
    /// walk, so the Cuuldurach raid went through the middle of the zone (2026-10-13). A leg that no longer proves keeps
    /// its chord and is reported.
    /// Env: OFFLINE_DAOC_NAV_ROOT (folder with navmesh/ and lib/Detour.dll), OFFLINE_DAOC_ROADS_IN (roads.json),
    /// OFFLINE_DAOC_ROADS_GEOMETRY (roads.candidates.json from roadgraph.py: each zone's x, y, w, h),
    /// OFFLINE_DAOC_ROADS_OUT (roads.json to write).
    /// </summary>
    [TestFixture, Explicit("Zone road weight tool"), NonParallelizable]
    public class UT_ZoneRoadWeights
    {
        [Test]
        public void WeighZoneRoads()
        {
            string root = Environment.GetEnvironmentVariable("OFFLINE_DAOC_NAV_ROOT");
            string input = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ROADS_IN");
            string geometryPath = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ROADS_GEOMETRY");
            string output = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ROADS_OUT");
            Assume.That(root != null && input != null && geometryPath != null && output != null);
            string previous = Environment.CurrentDirectory;
            Environment.CurrentDirectory = root;
            var nav = PathfindingProvider.LocalPathfindingMgr;
            using JsonDocument roads = JsonDocument.Parse(File.ReadAllText(input));
            using JsonDocument geometry = JsonDocument.Parse(File.ReadAllText(geometryPath));
            var zonesOut = new SortedDictionary<int, object>();
            try
            {
                foreach (JsonProperty entry in roads.RootElement.GetProperty("zones").EnumerateObject())
                {
                    var watch = System.Diagnostics.Stopwatch.StartNew();
                    ushort id = ushort.Parse(entry.Name);
                    JsonElement g = geometry.RootElement.GetProperty("zones").GetProperty(entry.Name);
                    var zone = new Zone(null, id, $"zone{id}", g.GetProperty("x").GetInt32(), g.GetProperty("y").GetInt32(),
                        g.GetProperty("w").GetInt32(), g.GetProperty("h").GetInt32(), id, false, 0, false, 0, 0, 0, 0, 0);
                    int[][] anchors = entry.Value.GetProperty("anchors").EnumerateArray()
                        .Select(a => a.EnumerateArray().Select(v => v.GetInt32()).ToArray()).ToArray();
                    int[][] edges = entry.Value.GetProperty("edges").EnumerateArray()
                        .Select(e => e.EnumerateArray().Take(2).Select(v => v.GetInt32()).ToArray()).ToArray();
                    Vector3 At(int i) => new(anchors[i][0], anchors[i][1], anchors[i][2]);
                    var lengths = new int[edges.Length];
                    int unproven = 0, longer = 0;
                    LocalPathfindingMgr.LoadNavMesh(zone);
                    try
                    {
                        Parallel.For(0, edges.Length, new ParallelOptions { MaxDegreeOfParallelism = 6 }, i =>
                        {
                            float chord = Vector3.Distance(At(edges[i][0]), At(edges[i][1]));
                            float walked = AutonomousZoneItinerary.CorridorLength(nav, zone, At(edges[i][0]), At(edges[i][1]));
                            if (float.IsNaN(walked)) { System.Threading.Interlocked.Increment(ref unproven); walked = chord; }
                            else if (walked > chord * 1.5f + 500) System.Threading.Interlocked.Increment(ref longer);
                            lengths[i] = (int)MathF.Ceiling(Math.Max(chord, walked));
                        });
                    }
                    finally { LocalPathfindingMgr.UnloadNavMesh(zone); }
                    zonesOut[id] = new
                    {
                        anchors,
                        edges = edges.Select((e, i) => new[] { e[0], e[1], lengths[i] }).ToArray()
                    };
                    TestContext.Progress.WriteLine($"zone {id}: {edges.Length} legs weighed, {longer} walk over 1.5x their chord, " +
                                                   $"{unproven} no longer prove (chord kept), {watch.Elapsed.TotalSeconds:F0}s");
                }
            }
            finally { Environment.CurrentDirectory = previous; }
            File.WriteAllText(output, JsonSerializer.Serialize(new
            {
                version = 1,
                cell = roads.RootElement.GetProperty("cell").GetInt32(),
                zones = zonesOut.ToDictionary(z => z.Key.ToString(), z => z.Value)
            }));
        }
    }
}
