using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Fixes found while reviewing other Offline DAoC forks on 2026-10-27, and issue #25.
    /// </summary>
    [TestFixture]
    public class UT_ForkPicksOct27
    {
        // Issue #25: a warband walking to a distant frontier medallion merchant proved up to 18 multi-zone routes every
        // 15 seconds per bot and stalled the NpcService tick for about a second.
        [Test]
        public void AMerchantSpotIsSearchedForOnlyFromTheMerchantsZone()
        {
            Assert.That(AutonomousSupplyMerchantSpace.ResolvesSpotFrom((ushort)163, (ushort)163), Is.True);
            Assert.That(AutonomousSupplyMerchantSpace.ResolvesSpotFrom((ushort)166, (ushort)163), Is.False, "another frontier zone walks first");
            Assert.That(AutonomousSupplyMerchantSpace.ResolvesSpotFrom(null, (ushort)163), Is.False);
            Assert.That(AutonomousSupplyMerchantSpace.ResolvesSpotFrom((ushort)163, null), Is.False);
        }

        // Found by stefanrows/OfflineDAoC 0.345.0: before the first pass, now - long.MinValue overflowed and the live clock
        // always returned early.
        [Test]
        public void TheFirstLiveSiegeExpiryPassRuns()
        {
            Assert.That(AutonomousRvrEventLayer.ExpireThrottled(1_000_000, long.MinValue), Is.False);
            Assert.That(AutonomousRvrEventLayer.ExpireThrottled(0, long.MinValue), Is.False);
        }

        [Test]
        public void LaterSiegeExpiryPassesAreThrottledToTwiceASecond()
        {
            long interval = AutonomousRvrEventLayer.ExpireIntervalMilliseconds;
            Assert.That(AutonomousRvrEventLayer.ExpireThrottled(1_000_100, 1_000_000), Is.True);
            Assert.That(AutonomousRvrEventLayer.ExpireThrottled(1_000_000 + interval, 1_000_000), Is.False);
            Assert.That(AutonomousRvrEventLayer.ExpireThrottled(999_000, 1_000_000), Is.False, "a clock behind the last pass runs");
        }

        // From rambodolphin13/OfflineDAoC 7a8ae69: an ended effect left in the service pulsed forever.
        [Test]
        public void EndedEffectsLeaveTheServiceUnlessRestarting()
        {
            Assert.That(EffectService.IsStaleEndedEffect(ended: true, starting: false, enabling: false), Is.True);
            Assert.That(EffectService.IsStaleEndedEffect(ended: true, starting: true, enabling: false), Is.False);
            Assert.That(EffectService.IsStaleEndedEffect(ended: true, starting: false, enabling: true), Is.False);
            Assert.That(EffectService.IsStaleEndedEffect(ended: false, starting: false, enabling: false), Is.False);
        }
    }
}
