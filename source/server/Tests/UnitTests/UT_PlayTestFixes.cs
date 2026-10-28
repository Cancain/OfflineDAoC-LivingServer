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
