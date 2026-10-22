namespace DOL.GS
{
    /// <summary>Lair anchors verified against the client mound geometry (not terrain beneath it).
    /// Flight coordinates are transient, never a spawn/home location.</summary>
    public static class DragonLairPlacement
    {
        public static Point3D Home(eRealm realm) => realm switch
        {
            eRealm.Albion => new Point3D(391326, 755351, 391),
            eRealm.Midgard => new Point3D(708811, 1021459, 3014),
            eRealm.Hibernia => new Point3D(408646, 706432, 2965),
            _ => throw new System.ArgumentOutOfRangeException(nameof(realm))
        };

        public static void Restore(GameNPC dragon, eRealm realm)
        {
            Point3D home = Home(realm);
            dragon.X = home.X;
            dragon.Y = home.Y;
            dragon.Z = home.Z;
            dragon.Flags = GroundFlags(dragon.Flags);
        }

        /// <summary>Each dragon takes no damage beyond this distance from its lair (its LairRadius).</summary>
        public const int LairRadius = 2000;

        /// <summary>The dragon's realm, or None for anything that is not one of the three dragons.</summary>
        public static eRealm DragonRealm(GameNPC npc) => npc switch
        {
            AlbGolestandt => eRealm.Albion,
            MidGjalpinulva => eRealm.Midgard,
            HibCuuldurach => eRealm.Hibernia,
            _ => eRealm.None
        };

        /// <summary>
        /// A dragon outside its lair, where it is immune. 2026-10-20: Gjalpinulva stood at 100% for an hour with
        /// 130-170 Midgard raiders on her aggro list; the fight was 2,600 units from her lair, inside her 2,500
        /// tether (so the tether rule never applied) but outside the 2,000 lair where she takes damage.
        /// </summary>
        public static bool IsOutOfLair(GameNPC npc) =>
            DragonRealm(npc) is var realm && realm != eRealm.None && npc.IsAlive && !npc.IsWithinRadius(Home(realm), LairRadius);

        public static bool IsOutOfLair(int dx, int dy) => (long)dx * dx + (long)dy * dy > (long)LairRadius * LairRadius;

        public static GameNPC.eFlags GroundFlags(GameNPC.eFlags flags) => flags & ~GameNPC.eFlags.FLYING;
        public static bool CanReceiveDamageFrom(GameObject source) => source != null && CanReceiveDamageType(source.GetType());
        public static bool CanReceiveDamageType(System.Type type) => type != null && typeof(GameLiving).IsAssignableFrom(type);
    }
}
