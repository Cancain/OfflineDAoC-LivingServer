namespace DOL.GS
{
    /// <summary>
    /// Explicit offline encounter adaptations. Bot raids cannot recover safely from
    /// scripted jail/air teleports or satisfy player-only split-position puzzles.
    /// Normal attacks, adds, health, resistances, and death/respawn chains remain active.
    /// </summary>
    public static class EpicEncounterMechanics
    {
        public static bool AllowDisplacement => false;
        public static bool AllowPositionPuzzle => false;
        public static bool AllowInvulnerableHazards => false;
        public static bool AllowAddShield => false;
        // Torst/Hurika keep their original database perches, attacks and loot.
        // Their unsupported aerial patrol/pull puzzle is separate from dragons'
        // existing fly/land cycle, which is deliberately not affected here.
        public static bool AllowGlacierGriffonPatrol => false;

        /// <summary>
        /// The scripted bosses of the epic dungeons, Summoner's Hall and Darkness Falls reset (walk home, full health,
        /// adds and phases cleared) on any brain turn with an empty aggro list. In a raid of 200 the list can be empty
        /// for a moment while the boss is still being hit, and Hurionthex in Galladoria went from 31% back to full
        /// that way, again and again (2026-10-14). The reset now waits until the boss has been out of combat for
        /// <see cref="ResetQuietMilliseconds"/>; a wiped or departed raid still resets it as before.
        /// </summary>
        public const int ResetQuietMilliseconds = 8_000;

        /// <summary>
        /// Princes Ba'alorien and Asmoien in Darkness Falls devour pets near them and heal by the pet's health. They ate
        /// every pet within 2,000 units on every brain turn, so a raid with pet classes could never wound them
        /// (Asmoien skipped at 100% with raiders beside him, 2026-10-15). Mechanic change (owner, 2026-10-14: change
        /// mechanics rather than health): one pet every five seconds, the nearest; the heal per pet is unchanged.
        /// </summary>
        public const int PetDevourIntervalMilliseconds = 5_000;

        public static bool FightIsOver(GameNPC boss) => boss == null || !boss.IsAlive || !boss.InCombatInLast(ResetQuietMilliseconds);
    }
}
