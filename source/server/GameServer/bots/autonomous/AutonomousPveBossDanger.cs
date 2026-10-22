using System;
using System.Collections.Generic;
using System.Threading;

namespace DOL.GS;

/// <summary>
/// Places where a monster far above the victim's level killed an autonomous bot. Players learn to keep away
/// from such a spot; so do the bots: no XP camp within <see cref="AvoidRadius"/> of a remembered spot for
/// <see cref="Lifetime"/>, and a levelling bot counts a straight walk past one as a long trip, so it usually
/// picks another camp. In memory only: a restart forgets.
///
/// Ported from stefanrows/OfflineDAoC (AutonomousPveBossDanger, GPL-3.0), where two named bosses killed
/// level-50 bots about 5,500 times in 19 hours. Here (2026-10-19, one hour): a merucha camp (levels 30-33)
/// on the Connacht road killed 18 bots of levels 10-17 on their way to Muire Tomb and Silvermine camps, and
/// 159 bots under level 20 died to red or purple monsters, 126 of them before reaching their camp.
/// </summary>
public static class AutonomousPveBossDanger
{
    /// <summary>A killer this many levels above its victim marks the spot.</summary>
    public const int LevelGap = 10;
    public const float AvoidRadius = 3_000;
    /// <summary>A straight walk that passes this close to a spot counts as passing it.</summary>
    public const float RouteCorridor = 1_500;
    /// <summary>Minutes a levelling bot adds to a camp whose route passes a spot (TravelWeightPercent: about 10%).</summary>
    public const double RoutePenaltyMinutes = 30;
    public static readonly TimeSpan Lifetime = TimeSpan.FromHours(6);
    private const int MaximumSpots = 512;

    // The killer's level: a spot only warns bots it is still far above (a level-30 camp that kills level-12
    // bots is an ordinary camp for a level-28 bot).
    private readonly record struct Spot(ushort RegionId, int X, int Y, int KillerLevel, DateTime Utc);

    public static bool Warns(int killerLevel, int botLevel) => killerLevel >= botLevel + LevelGap;

    private static readonly object Sync = new();
    // Deaths publish a new bounded snapshot; camp planners never hold a shared
    // lock while checking thousands of candidate cells.
    private static Spot[] _spots = [];

    /// <summary>Whether a death marks its place: a monster (not a player, bot or pet) far above the victim.</summary>
    public static bool Marks(string killerKind, int killerLevel, int victimLevel) =>
        string.Equals(killerKind, "monster", StringComparison.Ordinal) && killerLevel >= victimLevel + LevelGap;

    public static int Count => Volatile.Read(ref _spots).Length;

    public static void Record(ushort regionId, int x, int y, int killerLevel, DateTime utc)
    {
        lock (Sync)
        {
            var spots = new List<Spot>(_spots.Length + 1);
            foreach (Spot spot in _spots)
                if (utc - spot.Utc <= Lifetime)
                    spots.Add(spot);
            if (spots.Count >= MaximumSpots)
                spots.RemoveAt(0);
            spots.Add(new Spot(regionId, x, y, killerLevel, utc));
            Volatile.Write(ref _spots, spots.ToArray());
        }
    }

    public static bool IsNear(ushort regionId, int x, int y, int botLevel, DateTime utc)
    {
        foreach (Spot spot in Volatile.Read(ref _spots))
        {
            if (spot.RegionId != regionId || utc - spot.Utc > Lifetime || !Warns(spot.KillerLevel, botLevel))
                continue;
            double dx = (double)spot.X - x, dy = (double)spot.Y - y;
            if (dx * dx + dy * dy <= (double)AvoidRadius * AvoidRadius)
                return true;
        }
        return false;
    }

    /// <summary>Remembered spots within <paramref name="radius"/> that warn a bot of this level (for route bends).</summary>
    public static List<(int X, int Y, int KillerLevel)> SpotsNear(ushort regionId, int x, int y, int botLevel, DateTime utc, float radius)
    {
        var near = new List<(int, int, int)>();
        foreach (Spot spot in Volatile.Read(ref _spots))
        {
            if (spot.RegionId != regionId || utc - spot.Utc > Lifetime || !Warns(spot.KillerLevel, botLevel))
                continue;
            double dx = (double)spot.X - x, dy = (double)spot.Y - y;
            if (dx * dx + dy * dy <= (double)radius * radius)
                near.Add((spot.X, spot.Y, spot.KillerLevel));
        }
        return near;
    }

    /// <summary>Whether the straight walk from one point to another in the same region passes a remembered spot.</summary>
    public static bool RouteCrosses(ushort regionId, int fromX, int fromY, int toX, int toY, int botLevel, DateTime utc)
    {
        foreach (Spot spot in Volatile.Read(ref _spots))
        {
            if (spot.RegionId != regionId || utc - spot.Utc > Lifetime || !Warns(spot.KillerLevel, botLevel))
                continue;
            if (DistanceToSegment(spot.X, spot.Y, fromX, fromY, toX, toY) <= RouteCorridor)
                return true;
        }
        return false;
    }

    public static double DistanceToSegment(double px, double py, double ax, double ay, double bx, double by)
    {
        double dx = bx - ax, dy = by - ay, lengthSquared = dx * dx + dy * dy;
        double t = lengthSquared <= 0 ? 0 : Math.Clamp(((px - ax) * dx + (py - ay) * dy) / lengthSquared, 0, 1);
        double cx = ax + t * dx - px, cy = ay + t * dy - py;
        return Math.Sqrt(cx * cx + cy * cy);
    }

    /// <summary>Tests only.</summary>
    public static void Clear()
    {
        lock (Sync)
            Volatile.Write(ref _spots, []);
    }
}
