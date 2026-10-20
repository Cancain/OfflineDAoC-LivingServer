namespace DOL.GS;

/// <summary>
/// Ordinary XP camps belong to the realm whose frontier contains them. The
/// frontier itself remains traversable for RvR, defence and realm events;
/// those activities must not use this PvE-only assignment gate.
/// </summary>
public static class AutonomousOrdinaryPveRealmPolicy
{
    public static bool CanAssignCamp(eRealm botRealm, ushort regionId, ushort zoneId)
    {
        eRealm frontierOwner = (regionId, zoneId) switch
        {
            (1, 11 or 12 or 14 or 15) => eRealm.Albion,
            (100, 111 or 112 or 113 or 115) => eRealm.Midgard,
            (200, 210 or 211 or 212 or 214) => eRealm.Hibernia,
            _ => eRealm.None
        };

        // Other regions, including the shared Darkness Falls region, continue
        // through the existing realm, dungeon and navmesh access policies.
        return frontierOwner == eRealm.None || frontierOwner == botRealm;
    }

    /// <summary>The Shrouded Isles regions (Albion, Midgard, Hibernia).</summary>
    public static bool IsShroudedIsles(ushort regionId) => regionId is 51 or 151 or 181;

    /// <summary>
    /// The lowest level (the bot's, or its party's average) that takes XP camps in the Shrouded Isles.
    /// 2026-10-19: level-1 Midgard parties were sent to level 5-11 camps in Aegir's Landing; scimitar cats
    /// (levels 18-21) that roam there killed level-1 bots 201 times in three hours, mostly on the walk from
    /// the Aegirhamn bind to the party's meetup. New bots level in their realm's classic zones first.
    /// </summary>
    public const int ShroudedIslesMinimumLevel = 10;

    public static bool CanAssignCamp(eRealm botRealm, ushort regionId, ushort zoneId, int planningLevel) =>
        CanAssignCamp(botRealm, regionId, zoneId) && (planningLevel >= ShroudedIslesMinimumLevel || !IsShroudedIsles(regionId));
}
