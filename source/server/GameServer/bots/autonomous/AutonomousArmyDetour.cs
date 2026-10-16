using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using DOL.GS.Keeps;

namespace DOL.GS;

/// <summary>
/// The marching army's way around enemy keeps. Run 10 (2026-10-15): Midgard's relic army marched 185,000 units from its
/// portal keep to Dun Dagda straight past Hibernia's keeps and towers and through the defenders' rally at Dun Scathaig;
/// 146 marchers died on the way (Hibernian bots, Sentinels, keep guards) and 11 reached the relic keep. The march leader
/// now walks to a point beside the first enemy keep ahead of it before going on, and keeps well clear of the keep where
/// the defenders gather.
/// </summary>
public static class AutonomousArmyDetour
{
    public const float KeepClearance = 6_000f;
    public const float RallyClearance = 12_000f;
    public const float DetourMargin = 4_000f;
    public const float ReachedRadius = 1_500f;

    public readonly record struct Hazard(Vector2 Center, float Radius);

    /// <summary>
    /// The first hazard the straight line from <paramref name="from"/> to <paramref name="to"/> passes within its radius
    /// (ignoring hazards behind the start, past the target, or with the start or target inside them), and the point beside
    /// it, on the start's side of the line, <see cref="DetourMargin"/> outside its radius. Null when the line is clear.
    /// </summary>
    public static Vector2? FirstDetour(Vector2 from, Vector2 to, IEnumerable<Hazard> hazards)
    {
        Vector2 line = to - from;
        float length = line.Length();
        if (length < 1) return null;
        Vector2 dir = line / length;
        (Hazard Hazard, float Along)? first = null;
        foreach (Hazard hazard in hazards)
        {
            if (Vector2.Distance(from, hazard.Center) <= hazard.Radius || Vector2.Distance(to, hazard.Center) <= hazard.Radius)
                continue;
            float along = Vector2.Dot(hazard.Center - from, dir);
            if (along <= 0 || along >= length) continue;
            float off = MathF.Abs(Cross(dir, hazard.Center - from));
            if (off >= hazard.Radius) continue;
            if (first == null || along < first.Value.Along) first = (hazard, along);
        }
        if (first == null) return null;
        Hazard h = first.Value.Hazard;
        // Perpendicular on the side of the line the hazard is not on.
        Vector2 normal = new(-dir.Y, dir.X);
        float side = Cross(dir, h.Center - from) > 0 ? -1 : 1;
        return h.Center + normal * side * (h.Radius + DetourMargin);
    }

    private static float Cross(Vector2 a, Vector2 b) => a.X * b.Y - a.Y * b.X;

    /// <summary>Enemy keeps and towers of the region (not the target), and the defenders' rally keep with the wider radius.</summary>
    public static Hazard[] HazardsFor(ushort region, eRealm marcher, AbstractGameKeep target)
    {
        var keeps = GameServer.KeepManager.GetKeepsOfRegion(region).Where(keep => keep != target && !keep.IsPortalKeep).ToArray();
        AbstractGameKeep rally = keeps.Where(keep => keep.Realm == target.Realm &&
                Vector2.DistanceSquared(new(keep.X, keep.Y), new(target.X, target.Y)) >= 3_000f * 3_000f)
            .OrderBy(keep => Vector2.DistanceSquared(new(keep.X, keep.Y), new(target.X, target.Y))).FirstOrDefault();
        return keeps.Where(keep => keep.Realm != marcher)
            .Select(keep => new Hazard(new(keep.X, keep.Y), keep == rally ? RallyClearance : KeepClearance)).ToArray();
    }
}
