using System.Linq;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Owner, 2026-10-20: a party that is already in a dungeon also clears its boss when the boss is a quest target at
    /// the party's level or has its own drops; dungeons themselves are not made more attractive.
    /// </summary>
    [TestFixture]
    public class UT_DungeonBossGoals
    {
        // party level, party size, boss level, quest minimum level (0 = no quest), own drops
        [TestCase(16, 6, 16, 15, false, true)]    // Favonius Facilis, "Willing Sacrifice" (15+), a level-16 party of six
        [TestCase(11, 6, 16, 15, false, false)]   // more than three levels under the quest's level
        [TestCase(16, 5, 17, 17, false, true)]    // Muire Tomb: a level-16 party, "Rest in Peace" starts at 17
        [TestCase(11, 5, 12, 13, false, true)]    // Nisse's Lair: Rygnol (12) at level 11, quest at 13
        [TestCase(16, 2, 16, 15, false, false)]   // a pair is not a boss party
        [TestCase(16, 6, 16, 0, false, false)]    // no quest and no drops: no reason to go
        [TestCase(33, 4, 39, 0, true, false)]     // Scratch (39) is red to a party of four at 33
        [TestCase(33, 6, 39, 0, true, true)]      // but a fight for six
        [TestCase(30, 6, 35, 35, false, false)]   // Te'Bui's quests start at 35
        [TestCase(35, 6, 35, 35, false, true)]
        [TestCase(50, 8, 20, 17, false, false)]   // grey: nothing left to gain
        [TestCase(30, 8, 52, 0, true, false)]     // purple: not a fight to pick
        public void APartyGoesForABossWithAReasonAndAFightItCanTake(int level, int size, int bossLevel, int questMin, bool drops, bool goes) =>
            Assert.That(AutonomousDungeonBossGoals.Qualifies(level, size, bossLevel, questMin, drops), Is.EqualTo(goes));

        [Test]
        public void QuestTargetsAreTheNamedKillsWithTheirRegions()
        {
            var targets = AutonomousDungeonBossGoals.QuestTargets(
                "|Anilius;21|Favonius Facilis;21|Virilus;21|forgotten promise;21||Acolyte Nascita;21|High Priest Andania;21|Brother Codeth;1").ToArray();
            Assert.That(targets.Select(t => t.Name), Does.Contain("Favonius Facilis").And.Not.Contain("forgotten promise"));
            Assert.That(targets.First(t => t.Name == "Favonius Facilis").Region, Is.EqualTo(21));
            Assert.That(AutonomousDungeonBossGoals.QuestTargets(null), Is.Empty);
            Assert.That(AutonomousDungeonBossGoals.QuestTargets("Te'Bui;125").Single(), Is.EqualTo(("Te'Bui", (ushort)125)));
        }

        [Test]
        public void TheReasonNamesTheQuestOrTheDrop()
        {
            AutonomousDungeonBossGoals.SetForTests(new[] { new AutonomousDungeonBossGoals.Boss("Favonius Facilis", 21, "Willing Sacrifice", 15) }, new[] { "Scratch" });
            Assert.Multiple(() =>
            {
                Assert.That(AutonomousDungeonBossGoals.TryGetQuestBoss(21, "favonius facilis", out var boss), Is.True);
                Assert.That(AutonomousDungeonBossGoals.Reason(boss, false), Is.EqualTo("for the Willing Sacrifice quest"));
                Assert.That(AutonomousDungeonBossGoals.TryGetQuestBoss(22, "Favonius Facilis", out _), Is.False, "another dungeon");
                Assert.That(AutonomousDungeonBossGoals.HasOwnDrops("Scratch"), Is.True);
                Assert.That(AutonomousDungeonBossGoals.Reason(new AutonomousDungeonBossGoals.Boss("Scratch", 220, "", 0), true), Is.EqualTo("for its rare drop"));
            });
        }
    }
}
