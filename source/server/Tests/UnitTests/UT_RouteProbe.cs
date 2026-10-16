using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Numerics;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Tool: route checks on the real meshes for one zone, as the server runs them. Read only.
    /// Env: OFFLINE_DAOC_NAV_ROOT (folder with navmesh/ and lib/Detour.dll), OFFLINE_DAOC_PROOF_OUT,
    /// OFFLINE_DAOC_ZONE = "zoneId:offsetX:offsetY" (8192-unit cells, as the Zones table),
    /// OFFLINE_DAOC_PAIRS = "x,y,z>x,y,z;..." : direct corridor, zone-road route and approach (TryResolve, radius 220) per pair,
    /// OFFLINE_DAOC_FORMATIONS = "x,y,z;..." : formation posts (RealmRaidFormation) for every party slot around each centre.
    /// </summary>
    [TestFixture, Explicit("Route probe tool"), NonParallelizable]
    public class UT_RouteProbe
    {
        [Test]
        public void ProbeRoutes()
        {
            string root = Environment.GetEnvironmentVariable("OFFLINE_DAOC_NAV_ROOT");
            string output = Environment.GetEnvironmentVariable("OFFLINE_DAOC_PROOF_OUT");
            string zoneSpec = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ZONE");
            Assume.That(root != null && output != null && zoneSpec != null);
            int[] z = zoneSpec.Split(':').Select(int.Parse).ToArray();
            static Vector3[] Points(string s) => (s ?? "").Split(new[] { ';', '>' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(p => p.Split(',').Select(float.Parse).ToArray()).Select(v => new Vector3(v[0], v[1], v[2])).ToArray();
            string previous = Environment.CurrentDirectory;
            Environment.CurrentDirectory = root;
            var nav = PathfindingProvider.LocalPathfindingMgr;
            var zone = new Zone(null, (ushort)z[0], $"zone{z[0]}", z[1] * 8192, z[2] * 8192, 65536, 65536, (ushort)z[0], false, 0, false, 0, 0, 0, 0, 0);
            var lines = new List<string>();
            LocalPathfindingMgr.LoadNavMesh(zone);
            try
            {
                foreach (string pair in (Environment.GetEnvironmentVariable("OFFLINE_DAOC_PAIRS") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries))
                {
                    Vector3[] p = Points(pair);
                    var watch = System.Diagnostics.Stopwatch.StartNew();
                    bool direct = AutonomousZoneItinerary.HasDirectCorridor(nav, zone, p[0], p[1]);
                    bool road = AutonomousZoneRoads.TryRoute(nav, zone, p[0], p[1], out Vector3[] via);
                    bool approach = AutonomousZonePointApproach.TryResolve(nav, zone, p[0], p[1], 220, out Vector3 point);
                    bool floor = AutonomousNavigationSurface.TryFloor(nav, zone, p[0], out Vector3 under);
                    bool endFloor = AutonomousNavigationSurface.TryFloor(nav, zone, p[1], out _);
                    var nodes = new WrappedPathfindingNode[512];
                    PathfindingResult path = nav.GetPathStraight(zone, p[0], p[1], nav.DefaultFilters, nodes);
                    string last = path.NodeCount > 0 && path.NodeCount <= nodes.Length ? nodes[path.NodeCount - 1].Position.ToString() : "-";
                    lines.Add($"  end floor={endFloor} nearestEnd={nav.GetClosestPoint(zone, p[1], 64, 64, 256, nav.DefaultFilters)} " +
                              $"los={nav.HasLineOfSight(zone, p[0], p[1], nav.DefaultFilters)} path={path.Status} nodes={path.NodeCount} last={last} " +
                              $"jumps={Enumerable.Range(0, Math.Min(path.NodeCount, nodes.Length)).Count(i => (nodes[i].Flags & EDtPolyFlags.Jump) != 0)}");
                    lines.Add($"{pair}: floor={floor}{(floor ? "" : $" nearest={nav.GetClosestPoint(zone, p[0], 64, 64, 256, nav.DefaultFilters)}")} " +
                              $"direct={direct} road={road}{(road ? $" via={via.Length}" : "")} approach={approach}{(approach ? $" at={point}" : "")} " +
                              $"area={AutonomousZoneRoads.AreaAt(zone, p[0])}->{AutonomousZoneRoads.AreaAt(zone, p[1])} {watch.ElapsedMilliseconds}ms");
                }
                foreach (Vector3 centre in Points(Environment.GetEnvironmentVariable("OFFLINE_DAOC_FORMATIONS")))
                {
                    var occupied = new List<Vector3>();
                    var failed = new List<int>();
                    for (int slot = 0; slot < RealmRaidRecruitmentPolicy.MaximumParties; slot++)
                    {
                        if (RealmRaidFormation.TryResolve(nav, zone, centre, slot, occupied, out Vector3 post)) occupied.Add(post);
                        else failed.Add(slot);
                    }
                    lines.Add($"formation {centre}: {occupied.Count}/{RealmRaidRecruitmentPolicy.MaximumParties} parties placed; no post for slots [{string.Join(",", failed)}]");
                }
            }
            finally
            {
                LocalPathfindingMgr.UnloadNavMesh(zone);
                Environment.CurrentDirectory = previous;
            }
            File.WriteAllLines(output, lines);
        }
    }
}
