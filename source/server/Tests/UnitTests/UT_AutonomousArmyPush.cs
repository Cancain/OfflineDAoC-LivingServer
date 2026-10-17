using System.Numerics;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>Run 12 (2026-10-15): the relic army fought on one ridge for 40+ minutes; a stalled column now pushes on.</summary>
    [TestFixture]
    public class UT_AutonomousArmyPush
    {
        [Test]
        public void StalledColumnPushesOnThenStops()
        {
            var state = new AutonomousArmyPush.State();
            Vector2 ridge = new(426464, 352192);
            long t = 1_000;
            Assert.That(AutonomousArmyPush.Update(ref state, ridge, t, out _), Is.False);
            Assert.That(AutonomousArmyPush.Update(ref state, ridge + new Vector2(500, 0), t + AutonomousArmyPush.StallMilliseconds - 1, out _), Is.False);
            Assert.That(AutonomousArmyPush.Update(ref state, ridge, t + AutonomousArmyPush.StallMilliseconds, out bool started), Is.True);
            Assert.That(started, Is.True);
            long pushEnd = t + AutonomousArmyPush.StallMilliseconds + AutonomousArmyPush.PushMilliseconds;
            Assert.That(AutonomousArmyPush.Update(ref state, ridge, pushEnd - 1, out started), Is.True);
            Assert.That(started, Is.False);
            Assert.That(AutonomousArmyPush.Update(ref state, ridge, pushEnd, out _), Is.False);
        }

        [Test]
        public void MarchingColumnNeverPushes()
        {
            var state = new AutonomousArmyPush.State();
            long t = 1_000;
            for (int i = 0; i < 20; i++)
                Assert.That(AutonomousArmyPush.Update(ref state, new Vector2(400_000 + i * 2_500, 350_000), t + i * 60_000, out _), Is.False);
        }
    }
}
