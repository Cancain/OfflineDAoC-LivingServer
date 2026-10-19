using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>Bot logic fixes from the overnight log of 2026-10-19 (7 hours, 650 bots online).</summary>
    [TestFixture]
    public class UT_BotLogicOct19
    {
        // Levelling solo bots favour camps they can reach soon; far camps keep a floor so bots still spread out.
        [TestCase(0.0, 100)]
        [TestCase(2.0, 92)]
        [TestCase(7.0, 50)]
        [TestCase(14.0, 20)]
        [TestCase(30.0, 10)]
        [TestCase(9999.0, 10)]     // no known crossing
        [TestCase(-1.0, 100)]      // unknown travel time: no penalty
        public void NearCampsWeighMoreButFarOnesStayPossible(double minutes, int percent) =>
            Assert.That(AutonomousBotDecisionEngine.TravelWeightPercent(minutes), Is.EqualTo(percent));

        [Test]
        public void TravelWeightNeverRisesWithDistance()
        {
            int last = 101;
            for (double minutes = 0; minutes < 60; minutes += 0.5)
            {
                int percent = AutonomousBotDecisionEngine.TravelWeightPercent(minutes);
                Assert.That(percent, Is.LessThanOrEqualTo(last), $"{minutes} minutes");
                last = percent;
            }
        }

        [TestCase(GameNPC.eFlags.FLYING, true, 2933, true)]      // the Runemaster's glider
        [TestCase(GameNPC.eFlags.FLYING, true, 1200, false)]
        [TestCase(GameNPC.eFlags.FLYING, false, 2933, false)]    // melee: the approach proof handles it
        [TestCase((GameNPC.eFlags)0, true, 2933, false)]
        public void CastersOnlyPickFlyersTheyCanAlreadyShoot(GameNPC.eFlags flags, bool ranged, double distance, bool skipped) =>
            Assert.That(AutonomousPveTargetPolicy.FlyerOutOfRangedReach(flags, ranged, distance), Is.EqualTo(skipped));

        [Test]
        public void ADeathNamesWhatKindOfThingKilledTheBot() =>
            Assert.That(AutonomousDeathDiagnostics.KillerKind(null), Is.EqualTo("none"));
    }
}
