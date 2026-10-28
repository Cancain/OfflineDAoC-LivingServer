using NUnit.Framework;

namespace DOL.GS.Tests
{
    /// <summary>Fixes from the 2026-10-27 evening classic-client play test.</summary>
    [TestFixture]
    public class UT_PlayTestFixes
    {
        [Test]
        public void AHorseTicketQuestionWithoutADestinationIsAnswered()
        {
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("where can i buy a horse ticket?", out string answer), Is.True);
            Assert.That(answer, Does.Contain("stable"));
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("how do i get a ticket", out _), Is.True);
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("where is the stable master", out _), Is.True);
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("selling tickets cheap", out _), Is.False, "no question");
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("where do i level at 20?", out _), Is.False, "not about tickets");
        }

        [Test]
        public void AGroupCallNoBotFitsGetsAnHonestReply()
        {
            // "lvl 2 viking lfg pst" with no bot under level 10 drew silence.
            for (int seed = 0; seed < 20; seed++)
            {
                string low = AutonomousBotChatCoordinator.NoneNearLevelReply(2, null, new System.Random(seed));
                string mid = AutonomousBotChatCoordinator.NoneNearLevelReply(25, null, new System.Random(seed));
                string healer = AutonomousBotChatCoordinator.NoneNearLevelReply(25, "healer", new System.Random(seed));
                Assert.That(low, Is.Not.Empty);
                Assert.That(mid, Does.Not.Contain("lowbie"));
                Assert.That(healer, Does.Contain("healer"));
                Assert.That(low + mid + healer, Does.Not.Contain("send me an invite"), "a bot that can't join never offers to");
            }
            Assert.That(AutonomousBotChatCoordinator.NoneNearLevelReplyChance, Is.InRange(0.5, 1.0));
        }

        [Test]
        public void OnlyAGroupmateNearThePlayerCallsTheFight()
        {
            // A groupmate across East Svealand said "assisting you" while the player fought alone near Mularn.
            Assert.That(AutonomousBotCombatCalls.SawTheFight(false, 800), Is.True);
            Assert.That(AutonomousBotCombatCalls.SawTheFight(false, AutonomousBotCombatCalls.FightHearingRadius), Is.True);
            Assert.That(AutonomousBotCombatCalls.SawTheFight(false, 25_000), Is.False);
            Assert.That(AutonomousBotCombatCalls.SawTheFight(false, null), Is.False, "another region");
            Assert.That(AutonomousBotCombatCalls.SawTheFight(true, null), Is.True, "its own fight");
        }

        [Test]
        public void AGamebotWalkingBackTalksLikeAPlayer()
        {
            foreach (string stage in new[] { "release", "stable", "mount", "dismount", "arrive", "walk" })
                for (int seed = 0; seed < 6; seed++)
                {
                    string line = GameBot.GamebotReturnLine(stage, new System.Random(seed), "Mularn", "East Svealand");
                    Assert.That(line, Is.Not.Empty, stage);
                    Assert.That(line, Does.Not.Contain("formation").And.Not.Contain("I am"), stage);
                    Assert.That(line, Is.EqualTo(line.ToLowerInvariant().Replace("mularn", "Mularn").Replace("east svealand", "East Svealand")), stage);
                }
            Assert.That(GameBot.GamebotReturnLine("mount", new System.Random(1), null, null), Does.Not.Contain("{"));
        }

        [Test]
        public void ABotNamedMidFightAnswersAfterIt()
        {
            for (int seed = 0; seed < 6; seed++)
            {
                string line = AutonomousBotChatCoordinator.AfterAFight("sure, send me an invite", new System.Random(seed));
                Assert.That(line, Does.EndWith("sure, send me an invite"));
                Assert.That(line.Length, Is.GreaterThan("sure, send me an invite".Length));
            }
            Assert.That(AutonomousBotChatCoordinator.NamedWhileFightingWaitMs, Is.InRange(30_000, 180_000));
        }

        [Test]
        public void AMerchantInteractionSpotIsSearchedOnlyNearTheMerchant()
        {
            // Issue #25: distant warbands ran 18 multi-zone route probes every 15 seconds and stalled NpcService.
            Assert.That(AutonomousSupplyMerchantSpace.ShouldResolveSpot(150), Is.True);
            Assert.That(AutonomousSupplyMerchantSpace.ShouldResolveSpot(AutonomousSupplyMerchantSpace.SpotSearchRange), Is.True);
            Assert.That(AutonomousSupplyMerchantSpace.ShouldResolveSpot(AutonomousSupplyMerchantSpace.SpotSearchRange + 1), Is.False);
            Assert.That(AutonomousSupplyMerchantSpace.ShouldResolveSpot(110_000), Is.False);
            Assert.That(AutonomousSupplyMerchantSpace.ShouldResolveSpot(int.MaxValue), Is.False, "another region");
            Assert.That(AutonomousSupplyMerchantSpace.RetryAfterFailureMs, Is.GreaterThanOrEqualTo(15_000));
        }
    }
}
