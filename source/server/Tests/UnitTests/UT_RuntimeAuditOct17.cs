using System;
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using Duty = DOL.GS.BotGroupInvite.Duty;
using Living = DOL.GS.AutonomousLivingServer;

namespace DOL.GS.Tests
{
    /// <summary>Runtime audit 2026-10-17: invitation duties, heard-scene writes and Living Server pruning.</summary>
    [TestFixture]
    public class UT_RuntimeAuditOct17
    {
        #region Invitations

        [Test]
        public void AFreeBotHasNoDutyAndNoBusyMessage()
        {
            Assert.That(BotGroupInvite.DutyOf(true, false, false, false, false, false, false), Is.EqualTo(Duty.None));
            Assert.That(BotGroupInvite.BusyMessage("Aldwin", Duty.None), Is.Null);
            Assert.That(BotGroupInvite.DutyOf((GameBot)null), Is.EqualTo(Duty.None));
        }

        [TestCase(false, false, false, false, false, false, false, Duty.Dead)]
        [TestCase(true, true, false, false, false, false, false, Duty.Siege)]
        [TestCase(true, false, true, false, false, false, false, Duty.Relic)]
        [TestCase(true, false, false, true, false, false, false, Duty.RvrEvent)]
        [TestCase(true, false, false, false, true, false, false, Duty.RealmRaid)]
        [TestCase(true, false, false, false, false, true, false, Duty.StableRoute)]
        [TestCase(true, false, false, false, false, false, true, Duty.Helper)]
        [TestCase(false, true, true, true, true, true, true, Duty.Dead)]
        [TestCase(true, true, true, true, true, true, true, Duty.Siege)]
        [TestCase(true, false, true, true, false, false, false, Duty.Relic)]
        public void EachDutyRefusesTheInvitation(bool alive, bool siege, bool relic, bool rvr, bool raid, bool stable, bool helper, Duty expected)
        {
            Duty duty = BotGroupInvite.DutyOf(alive, siege, relic, rvr, raid, stable, helper);
            Assert.That(duty, Is.EqualTo(expected));
            string message = BotGroupInvite.BusyMessage("Aldwin", duty);
            Assert.That(message, Does.StartWith("Aldwin "));
            Assert.That(message, Does.EndWith("."));
        }

        [Test]
        public void TheSiegeMessageSaysSo() =>
            Assert.That(BotGroupInvite.BusyMessage("Aldwin", Duty.Siege), Is.EqualTo("Aldwin is busy with a siege right now."));

        [Test]
        public void EveryDutyHasItsOwnMessage()
        {
            var duties = Enum.GetValues<Duty>().Where(duty => duty != Duty.None).ToArray();
            var messages = duties.Select(duty => BotGroupInvite.BusyMessage("X", duty)).ToArray();
            Assert.That(messages, Has.None.Null);
            Assert.That(messages.Distinct().Count(), Is.EqualTo(duties.Length));
        }

        #endregion

        #region Heard scenes

        private static OfflineBotSceneHeardRecord Heard(int realm, string scene) =>
            new() { HeardKey = $"{realm}:{scene}", Realm = realm, SceneId = scene };

        [Test]
        public void AResetDropsItsRealmsUnwrittenRowsAndKeepsLaterOnes()
        {
            var queue = new AutonomousBotDebates.HeardWriteQueue();
            queue.Add(Heard(1, "a"));
            queue.Add(Heard(2, "b"));
            queue.Reset(1);
            queue.Add(Heard(1, "c"));

            var (resets, adds) = queue.Take();
            Assert.That(resets, Is.EqualTo(new[] { 1 }));
            Assert.That(adds.Select(row => row.HeardKey), Is.EqualTo(new[] { "2:b", "1:c" }));

            var (againResets, againAdds) = queue.Take();
            Assert.That(againResets, Is.Empty);
            Assert.That(againAdds, Is.Empty);
        }

        [Test]
        public void ManyResetsOfARealmAreOneDelete()
        {
            var queue = new AutonomousBotDebates.HeardWriteQueue();
            queue.Reset(3);
            queue.Reset(3);
            queue.Reset(1);
            Assert.That(queue.Take().Resets, Is.EqualTo(new[] { 1, 3 }));
        }

        #endregion

        #region Living Server pruning

        private static LivingServerTable<(long BotId, string Killer), OfflineBotNemesisRecord> Nemeses(
            params (long Bot, string Killer, int Kills, string LastUtc)[] rows)
        {
            var table = new LivingServerTable<(long BotId, string Killer), OfflineBotNemesisRecord>("test", r => (r.BotId, r.KillerName));
            table.Load(rows.Select(row => new OfflineBotNemesisRecord
            {
                BotId = row.Bot, KillerName = row.Killer, Kills = row.Kills, LastUtc = row.LastUtc,
            }));
            return table;
        }

        [Test]
        public void RowsOfDeletedCharactersArePruned()
        {
            string now = DateTime.UtcNow.ToString("O");
            var nemeses = Nemeses((1, "Troll", 3, now), (2, "Kobold", 5, now), (3, "Bear", 1, now), (2, "Wolf", 1, now));
            Assert.That(Living.PruneOrphans(nemeses, row => row.BotId, new HashSet<long> { 1, 3 }), Is.EqualTo(2));
            Assert.That(nemeses.Count, Is.EqualTo(2));
            Assert.That(nemeses.TryGet((1, "Troll"), out _) && nemeses.TryGet((3, "Bear"), out _), Is.True);

            var memories = new LivingServerTable<(long BotId, string Player), OfflineBotMemoryRecord>("test", r => (r.BotId, r.PlayerName));
            memories.Load(new[] { new OfflineBotMemoryRecord { BotId = 9, PlayerName = "Chris" }, new OfflineBotMemoryRecord { BotId = 1, PlayerName = "Chris" } });
            Assert.That(Living.PruneOrphans(memories, row => row.BotId, new HashSet<long> { 1 }), Is.EqualTo(1));
            Assert.That(memories.TryGet((1, "Chris"), out _), Is.True);
        }

        [Test]
        public void AnEmptyOrMissingRosterPrunesNothing()
        {
            string now = DateTime.UtcNow.ToString("O");
            var nemeses = Nemeses((1, "Troll", 3, now), (2, "Kobold", 5, now));
            Assert.That(Living.PruneOrphans(nemeses, row => row.BotId, new HashSet<long>()), Is.Zero);
            Assert.That(Living.PruneOrphans(nemeses, row => row.BotId, null), Is.Zero);
            Assert.That(nemeses.Count, Is.EqualTo(2));
        }

        [Test]
        public void OnlyOldOneKillNemesesAreForgotten()
        {
            string old = DateTime.UtcNow.AddDays(-8).ToString("O");
            string recent = DateTime.UtcNow.AddDays(-2).ToString("O");
            var nemeses = Nemeses((1, "OldOnce", 1, old), (1, "OldTwice", 2, old), (1, "RecentOnce", 1, recent), (1, "Unreadable", 1, "?"));
            Assert.That(Living.PruneOldNemeses(nemeses), Is.EqualTo(1));
            Assert.That(nemeses.TryGet((1, "OldOnce"), out _), Is.False);
            Assert.That(nemeses.Count, Is.EqualTo(3));
            Assert.That(Living.NemesisPruneIntervalMs, Is.GreaterThanOrEqualTo(60 * 60_000L), "never a per-death or per-tick scan");
        }

        #endregion
    }
}
