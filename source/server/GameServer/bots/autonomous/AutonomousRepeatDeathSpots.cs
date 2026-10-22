using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

namespace DOL.GS;

/// <summary>
/// One bot's own deadly places: where a monster killed it <see cref="RepeatDeaths"/> or more times within
/// <see cref="ClusterRadius"/> in the last <see cref="Lifetime"/>, whatever the monster's level. The bot bends its
/// open-world routes around them and picks no camp beside them, as a player would after the third corpse run.
///
/// 2026-10-20 overnight run: <see cref="AutonomousPveBossDanger"/> only marks killers ten levels above the victim,
/// so it never warned a level-50 bot. Tadoelgan (level 50 Animist) died 72 times to yellow and blue glimmers about
/// 2,000 units from its Sheeroe Hills bind, walking back into the same pack after every release.
/// In memory only: a restart forgets.
/// </summary>
public static class AutonomousRepeatDeathSpots
{
    public const int RepeatDeaths = 3;
    public const float ClusterRadius = 1_200;
    /// <summary>The radius kept around a repeat-death spot (as <see cref="AutonomousPveDangerBypass.RememberedSpotRadius"/>).</summary>
    public const float AvoidRadius = 1_650;
    public static readonly TimeSpan Lifetime = TimeSpan.FromHours(3);
    private const int MaximumDeathsPerBot = 24;
    private const int MaximumBots = 8_192;

    public readonly record struct Death(ushort RegionId, int X, int Y, DateTime Utc);

    private static readonly ConcurrentDictionary<long, Death[]> Deaths = new();

    public static void Record(long botId, ushort regionId, int x, int y, DateTime utc)
    {
        if (Deaths.Count > MaximumBots) Deaths.Clear();
        Deaths.AddOrUpdate(botId, _ => [new Death(regionId, x, y, utc)], (_, old) =>
            old.Where(death => utc - death.Utc <= Lifetime).Append(new Death(regionId, x, y, utc))
                .TakeLast(MaximumDeathsPerBot).ToArray());
    }

    /// <summary>Pure rule: the spots (latest death of each cluster) where this many deaths fell close together recently.</summary>
    public static List<(int X, int Y)> Spots(IReadOnlyList<Death> deaths, ushort regionId, DateTime utc)
    {
        var recent = (deaths ?? []).Where(death => death.RegionId == regionId && utc - death.Utc <= Lifetime)
            .OrderByDescending(death => death.Utc).ToArray();
        var spots = new List<(int X, int Y)>();
        foreach (Death death in recent)
        {
            if (spots.Any(spot => Distance(spot.X, spot.Y, death.X, death.Y) <= ClusterRadius)) continue;
            if (recent.Count(other => Distance(other.X, other.Y, death.X, death.Y) <= ClusterRadius) >= RepeatDeaths)
                spots.Add((death.X, death.Y));
        }
        return spots;
    }

    public static List<(int X, int Y)> Spots(long botId, ushort regionId, DateTime utc) =>
        Deaths.TryGetValue(botId, out Death[] deaths) ? Spots(deaths, regionId, utc) : [];

    /// <summary>This bot's spots within <paramref name="radius"/> of a point, for route bends.</summary>
    public static List<(int X, int Y)> SpotsNear(long botId, ushort regionId, int x, int y, DateTime utc, float radius) =>
        Spots(botId, regionId, utc).Where(spot => Distance(spot.X, spot.Y, x, y) <= radius).ToList();

    /// <summary>All of this bot's spots in every region (computed once per camp plan).</summary>
    public static (ushort RegionId, int X, int Y)[] AllSpots(long botId, DateTime utc) =>
        Deaths.TryGetValue(botId, out Death[] deaths)
            ? deaths.Select(death => death.RegionId).Distinct()
                .SelectMany(region => Spots(deaths, region, utc).Select(spot => (region, spot.X, spot.Y))).ToArray()
            : [];

    /// <summary>Whether a camp at this point lies beside one of these spots.</summary>
    public static bool IsNear((ushort RegionId, int X, int Y)[] spots, ushort regionId, int x, int y)
    {
        foreach (var spot in spots)
            if (spot.RegionId == regionId && Distance(spot.X, spot.Y, x, y) <= AvoidRadius) return true;
        return false;
    }

    private static double Distance(int ax, int ay, int bx, int by)
    {
        double dx = (double)ax - bx, dy = (double)ay - by;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    /// <summary>Tests only.</summary>
    public static void Clear() => Deaths.Clear();
}
