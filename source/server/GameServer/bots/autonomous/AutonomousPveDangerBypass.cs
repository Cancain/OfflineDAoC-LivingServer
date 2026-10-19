using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;

namespace DOL.GS;

/// <summary>
/// Route bends for a solo levelling bot around monsters far above it and around remembered death spots
/// (<see cref="AutonomousPveBossDanger"/>). Pure decisions, testable; the controller checks every bend on the
/// navmesh before walking it.
///
/// Ported from stefanrows/OfflineDAoC (AutonomousRvrMobAvoidance, GPL-3.0), which bends RvR warbands around named
/// and far-above monsters. Here (2026-10-19): a merucha pack (levels 30-33) on the Connacht road killed 30 bots of
/// levels 10-17 in two hours; 22 of them had already seen it and chosen the existing one-monster sidestep (13) or a
/// new camp (9), and died anyway, some three times running from the same bind point.
/// </summary>
public static class AutonomousPveDangerBypass
{
    public readonly record struct Danger(Vector2 Center, float Radius, string Name, int Level);
    public readonly record struct MobView(Vector2 Position, int Level, string Name, bool Aggressive);

    public const float ScanRadius = 3_000;
    /// <summary>Only the next stretch of the route is bent; the rest is re-examined while walking.</summary>
    public const float LookAhead = 3_000;
    public const float Margin = 200;
    /// <summary>A bend costs at most this many extra units, otherwise the ordinary route-threat rules decide. Longer than
    /// stefanrows' 4,000 for warbands: a solo level 12 walking into three level-30 meruchas dies, so the long way is worth it.</summary>
    public const float MaximumDetour = 6_000;
    /// <summary>The radius kept around a remembered death spot.</summary>
    public const float RememberedSpotRadius = 1_650;

    public static ConColor Con(int actorLevel, int mobLevel) =>
        ConLevels.GetConColor(ConLevels.GetConLevel(Math.Clamp(actorLevel, 0, 127), Math.Clamp(mobLevel, 0, 127)));

    /// <summary>Red or purple to the bot: a fight a levelling solo bot doesn't survive.</summary>
    public static bool IsFarAbove(int actorLevel, int mobLevel) => Con(actorLevel, mobLevel) >= ConColor.RED;

    /// <summary>700 units plus 55 per level above the bot, at most 1,650 (stefanrows' AvoidanceRadius).</summary>
    public static float AvoidanceRadius(int actorLevel, int mobLevel) =>
        Math.Clamp(700 + Math.Max(0, mobLevel - actorLevel) * 55, 700, 1650);

    /// <summary>Every aggressive far-above monster, plus the remembered spots, as circles to keep out of.</summary>
    public static List<Danger> BuildDangers(int actorLevel, IEnumerable<MobView> mobs,
        IEnumerable<(int X, int Y, int KillerLevel)> rememberedSpots)
    {
        var dangers = new List<Danger>();
        foreach (MobView mob in mobs ?? [])
            if (mob.Aggressive && IsFarAbove(actorLevel, mob.Level))
                dangers.Add(new(mob.Position, AvoidanceRadius(actorLevel, mob.Level), mob.Name, mob.Level));
        foreach (var spot in rememberedSpots ?? [])
            dangers.Add(new(new(spot.X, spot.Y), RememberedSpotRadius, "remembered danger", spot.KillerLevel));
        return dangers;
    }

    /// <summary>
    /// Waypoints that take the next stretch of the route around the first danger in its way, shortest detour
    /// first. Empty when nothing blocks, when the goal or the walker is inside a danger (the camp choice and the
    /// combat rules own those), or when every bend costs more than <paramref name="maximumDetour"/>.
    /// </summary>
    public static Vector2[] BypassCandidates(Vector2 start, Vector2 goal, IReadOnlyList<Danger> dangers,
        float lookAhead = LookAhead, float maximumDetour = MaximumDetour)
    {
        if (dangers == null || dangers.Count == 0)
            return [];
        Vector2 delta = goal - start;
        float length = delta.Length();
        if (length < 1)
            return [];
        Vector2 direction = delta / length;
        float leg = Math.Min(length, lookAhead);

        Danger? blocking = null;
        float firstAlong = float.MaxValue;
        foreach (Danger danger in dangers)
        {
            if (Vector2.Distance(start, danger.Center) <= danger.Radius ||
                Vector2.Distance(goal, danger.Center) <= danger.Radius)
                continue;
            float along = Math.Clamp(Vector2.Dot(danger.Center - start, direction), 0, leg);
            if (Vector2.Distance(start + direction * along, danger.Center) >= danger.Radius)
                continue;
            if (along < firstAlong)
            {
                firstAlong = along;
                blocking = danger;
            }
        }
        if (blocking is not Danger block)
            return [];

        Vector2 normal = new(-direction.Y, direction.X);
        float side = Vector2.Dot(block.Center - start, normal);
        Vector2 preferred = side > 0 || side == 0 && ((int)start.X ^ (int)goal.Y) % 2 == 0 ? -normal : normal;
        var candidates = new List<(Vector2 Point, float Detour, int Order)>();
        int order = 0;
        foreach (Vector2 away in new[] { preferred, -preferred })
        {
            // Out to three radii (stefanrows: two): a pack of overlapping circles needs the wider swing.
            for (float scale = 1f; scale <= 3.01f; scale += 0.25f)
            {
                Vector2 point = block.Center + away * ((block.Radius + Margin) * scale);
                float detour = Vector2.Distance(start, point) + Vector2.Distance(point, goal) - length;
                if (detour > maximumDetour)
                    break;
                if (!LegClear(start, point, dangers) || !LegClear(point, goal, dangers, lookAhead))
                    continue;
                candidates.Add((point, detour, order));
                break;
            }
            order++;
        }
        return candidates.OrderBy(candidate => candidate.Detour).ThenBy(candidate => candidate.Order)
            .Select(candidate => candidate.Point).ToArray();
    }

    /// <summary>Whether a straight leg keeps clear of every danger (one containing the leg's end is ignored).</summary>
    public static bool LegClear(Vector2 start, Vector2 end, IReadOnlyList<Danger> dangers, float within = float.MaxValue)
    {
        Vector2 delta = end - start;
        float length = delta.Length();
        if (length < 1)
            return true;
        Vector2 direction = delta / length;
        float leg = Math.Min(length, within);
        foreach (Danger danger in dangers)
        {
            if (Vector2.Distance(end, danger.Center) <= danger.Radius)
                continue;
            float along = Math.Clamp(Vector2.Dot(danger.Center - start, direction), 0, leg);
            if (Vector2.Distance(start + direction * along, danger.Center) < danger.Radius)
                return false;
        }
        return true;
    }

    /// <summary>The point about <paramref name="lookAhead"/> units along a route (its end when shorter).</summary>
    public static Vector3 PointAlong(ReadOnlySpan<Vector3> route, float lookAhead)
    {
        if (route.Length == 0) return default;
        float walked = 0;
        for (int i = 1; i < route.Length; i++)
        {
            float step = Vector2.Distance(new(route[i - 1].X, route[i - 1].Y), new(route[i].X, route[i].Y));
            if (walked + step >= lookAhead && step > 0)
                return Vector3.Lerp(route[i - 1], route[i], (lookAhead - walked) / step);
            walked += step;
        }
        return route[^1];
    }
}
