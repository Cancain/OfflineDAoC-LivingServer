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
    /// Tool: a whole multi-zone trip on the real meshes as a bot walks it. Zone steps come from the server's planner
    /// (AutonomousZoneItinerary.ProbeNextStep); inside each zone the walk is the mover's Detour path, with the zone road
    /// route when Detour returns a partial path (Pathfinder.TryRoadPath). Reports the walked length, each leg, jump
    /// links used and a thinned list of waypoints. Read only.
    /// Env: OFFLINE_DAOC_NAV_ROOT, OFFLINE_DAOC_PROOF_OUT, OFFLINE_DAOC_ZONES and OFFLINE_DAOC_REGION as UT_ZoneStepProbe,
    /// OFFLINE_DAOC_TRIPS = "name=x,y,z>x,y,z>...;..." (start, then each target in turn: a raid's retained seams, then its
    /// staging post), OFFLINE_DAOC_STAGES = "from>to@x,y,z;..." (optional: plan a from->to trip toward the zone holding
    /// x,y,z first, aiming at that point, as the region-specific road staging does).
    /// </summary>
    [TestFixture, Explicit("Trip probe tool"), NonParallelizable]
    public class UT_TripProbe
    {
        [Test]
        public void ProbeTrips()
        {
            string root = Environment.GetEnvironmentVariable("OFFLINE_DAOC_NAV_ROOT");
            string output = Environment.GetEnvironmentVariable("OFFLINE_DAOC_PROOF_OUT");
            string zoneSpec = Environment.GetEnvironmentVariable("OFFLINE_DAOC_ZONES");
            string tripSpec = Environment.GetEnvironmentVariable("OFFLINE_DAOC_TRIPS");
            Assume.That(root != null && output != null && zoneSpec != null && tripSpec != null);
            ushort region = ushort.Parse(Environment.GetEnvironmentVariable("OFFLINE_DAOC_REGION") ?? "0");
            static Vector3 Point(string s) { float[] v = s.Split(',').Select(float.Parse).ToArray(); return new Vector3(v[0], v[1], v[2]); }
            var stages = (Environment.GetEnvironmentVariable("OFFLINE_DAOC_STAGES") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries)
                .Select(s => (From: ushort.Parse(s.Split('>')[0]), To: ushort.Parse(s.Split('>')[1].Split('@')[0]), Road: Point(s.Split('@')[1]))).ToList();
            string previous = Environment.CurrentDirectory;
            Environment.CurrentDirectory = root;
            var nav = PathfindingProvider.LocalPathfindingMgr;
            var lines = new List<string>();
            var zones = zoneSpec.Split(';', StringSplitOptions.RemoveEmptyEntries).Select(item =>
            {
                int[] v = item.Split(':').Select(int.Parse).ToArray();
                return new Zone(null, (ushort)v[0], $"zone{v[0]}", v[1], v[2], v[3], v[4], (ushort)v[0], false, 0, false, 0, 0, 0, 0, 0);
            }).ToList();
            Zone At(Vector3 p) => zones.FirstOrDefault(z => p.X >= z.XOffset && p.X < z.XOffset + z.Width && p.Y >= z.YOffset && p.Y < z.YOffset + z.Height);
            var nodes = new WrappedPathfindingNode[4096];
            try
            {
                foreach (Zone zone in zones) LocalPathfindingMgr.LoadNavMesh(zone);
                // OFFLINE_DAOC_DRAGON = "x,y,z": the dragon raid's staging posts (RealmRaidStaging) for the first parties.
                if (Environment.GetEnvironmentVariable("OFFLINE_DAOC_DRAGON") is string dragon)
                {
                    Vector3 home = Point(dragon);
                    var posts = new List<Vector3>();
                    for (int slot = 0; slot < 4; slot++)
                        if (RealmRaidStaging.TryDragonPost(nav, At(home), home, slot, posts, out Vector3 post)) posts.Add(post);
                    lines.Add("dragon staging " + string.Join(" ", posts.Select(p => $"{(int)p.X},{(int)p.Y},{(int)p.Z}")));
                }
                foreach (string trip in tripSpec.Split(';', StringSplitOptions.RemoveEmptyEntries))
                {
                    string name = trip.Split('=')[0];
                    Vector3[] points = trip.Split('=')[1].Split('>').Select(Point).ToArray();
                    Vector3 position = points[0];
                    var walked = new List<Vector3> { position };
                    float total = 0;
                    int jumps = 0;
                    bool ok = true;
                    var legs = new List<string>();
                    // One zone's walk, as the mover: Detour, then the road route for a far-short partial path.
                    bool Walk(Zone zone, Vector3 to, out float length)
                    {
                        length = 0;
                        AutonomousNavigationSurface.TryFloor(nav, zone, position, out Vector3 from);
                        PathfindingResult path = nav.GetPathStraight(zone, from, to, nav.DefaultFilters, nodes);
                        if (Pathfinder.TryRoadPath(nav, zone, from, to, nav.DefaultFilters, path, nodes, nodes.Length, out var road)) path = road;
                        if (path.NodeCount < 1) return false;
                        Vector3 last = from;
                        for (int i = 0; i < path.NodeCount; i++)
                        {
                            length += Vector3.Distance(last, nodes[i].Position);
                            last = nodes[i].Position;
                            walked.Add(last);
                            if ((nodes[i].Flags & EDtPolyFlags.Jump) != 0) jumps++;
                        }
                        position = last;
                        return path.Status == PathfindingStatus.PathFound || Vector3.Distance(last, to) <= 64;
                    }
                    for (int leg = 1; leg < points.Length && ok; leg++)
                    {
                        Vector3 goal = points[leg];
                        Zone target = At(goal);
                        float legLength = 0;
                        int crossings = 0;
                        while (ok && At(position) != target && crossings < 16)
                        {
                            Zone from = At(position);
                            Zone toward = target;
                            Vector3 aim = goal;
                            var stage = stages.FirstOrDefault(s => s.From == from.ID && s.To == target.ID);
                            if (stage.Road != default && At(stage.Road) is Zone via && via != from) { toward = via; aim = stage.Road; }
                            if (!AutonomousZoneItinerary.ProbeNextStep(zones, region, from, toward, position, aim, nav, out var step, new List<string>()))
                            { legs.Add($"  leg {leg}: no zone step {from.ID}->{toward.ID} from {position}"); ok = false; break; }
                            if (!Walk(from, step.Inside, out float inside)) { legs.Add($"  leg {leg}: no path in zone {from.ID} to crossing {step.Inside}"); ok = false; break; }
                            legLength += inside + Vector3.Distance(step.Inside, step.Outside);
                            legs.Add($"  leg {leg}: zone {from.ID} -> {At(step.Outside).ID} at {(int)step.Outside.X},{(int)step.Outside.Y},{(int)step.Outside.Z} ({inside:0} walked)");
                            position = step.Outside;
                            walked.Add(position);
                            crossings++;
                        }
                        if (!ok) break;
                        if (!Walk(target, goal, out float final)) { legs.Add($"  leg {leg}: no path in zone {target.ID} to {goal}"); ok = false; break; }
                        legLength += final;
                        total += legLength;
                        legs.Add($"  leg {leg} to {(int)goal.X},{(int)goal.Y},{(int)goal.Z}: {legLength:0} (last zone {final:0})");
                    }
                    lines.Add($"{name}: {(ok ? "COMPLETE" : "FAILED")} walked={total:0} straight={Vector3.Distance(points[0], points[^1]):0} jumps={jumps}");
                    lines.AddRange(legs);
                    var thinned = new List<Vector3>();
                    foreach (Vector3 p in walked)
                        if (thinned.Count == 0 || Vector3.Distance(thinned[^1], p) >= 2500) thinned.Add(p);
                    thinned.Add(walked[^1]);
                    lines.Add("  waypoints " + string.Join(" ", thinned.Select(p => $"{(int)p.X},{(int)p.Y},{(int)p.Z}")));
                }
            }
            finally
            {
                foreach (Zone zone in zones) LocalPathfindingMgr.UnloadNavMesh(zone);
                Environment.CurrentDirectory = previous;
            }
            File.WriteAllLines(output, lines);
            TestContext.Progress.WriteLine(lines.FirstOrDefault() ?? "no trips");
        }
    }
}
