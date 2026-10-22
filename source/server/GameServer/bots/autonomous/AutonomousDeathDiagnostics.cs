using System;
using System.Linq;
using DOL.Logging;

namespace DOL.GS
{
    /// <summary>
    /// One server-log line per autonomous gamebot death (AUTONOMOUS_BOT_DEATH): what it was doing, what killed it and
    /// how many were on it. The overnight log of 2026-10-19 had 3,553 deaths and nothing that named a killer, so the
    /// cause of the half that happen on the way to a camp could only be guessed.
    /// </summary>
    public static class AutonomousDeathDiagnostics
    {
        private static readonly Logger Log = LoggerManager.Create(typeof(AutonomousDeathDiagnostics));

        /// <summary>The killer's kind: a monster, a pet, an enemy bot, a real player or something else.</summary>
        public static string KillerKind(GameObject killer) => killer switch
        {
            null => "none",
            GamePlayer => "player",
            GameBot => "bot",
            GameNPC { Brain: DOL.AI.Brain.IControlledBrain } => "pet",
            GameNPC => "monster",
            _ => killer.GetType().Name,
        };

        public static void Record(GameBot bot, GameObject killer, string activityBefore)
        {
            if (bot?.IsAutonomousWorldBot != true)
                return;
            if (killer is GameLiving deadly && AutonomousPveBossDanger.Marks(KillerKind(killer), deadly.Level, bot.Level))
                AutonomousPveBossDanger.Record(bot.CurrentRegionID, bot.X, bot.Y, deadly.Level, DateTime.UtcNow);
            if (string.Equals(KillerKind(killer), "monster", StringComparison.Ordinal))
                AutonomousRepeatDeathSpots.Record(bot.DatabaseID, bot.CurrentRegionID, bot.X, bot.Y, DateTime.UtcNow);
            if (!Log.IsInfoEnabled)
                return;
            try
            {
                GameLiving living = killer as GameLiving;
                int attackers = bot.attackComponent?.AttackerTracker?.Attackers?.Count() ?? 0;
                string con = living != null ? ConLevels.GetConColor(bot.GetConLevel(living)).ToString() : "-";
                bool arrived = bot.GoalDiagnosticAttempt?.ArrivedUtc != null;
                int armor = bot.Inventory?.EquippedItems?.Count(item => item != null && item.Object_Type >= (int)eObjectType._FirstArmor &&
                    item.Object_Type <= (int)eObjectType._LastArmor) ?? -1;
                Log.Info($"AUTONOMOUS_BOT_DEATH bot=\"{bot.Name}\" id={bot.DatabaseID} level={bot.Level} class=\"{bot.ClassName}\" " +
                         $"realm={GlobalConstants.RealmToName(bot.Realm)} group={(bot.Group?.MemberCount ?? 1)} " +
                         $"killer=\"{killer?.Name}\" killerKind={KillerKind(killer)} killerLevel={living?.Level ?? 0} con={con} " +
                         $"attackers={attackers} armorPieces={armor} maxHealth={bot.MaxHealth} arrivedAtCamp={arrived} " +
                         $"activity=\"{activityBefore}\" goal=\"{bot.PersistentRecord?.CurrentGoal}\" " +
                         $"region={bot.CurrentRegionID} zone=\"{bot.CurrentZone?.Description}\" at={bot.X},{bot.Y},{bot.Z}");
            }
            catch (Exception exception)
            {
                Log.Warn("AUTONOMOUS_BOT_DEATH could not be written", exception);
            }
        }
    }
}
