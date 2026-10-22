using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Live run 2026-10-21: Lydsyg's area disease, cast from OnAttackEnemy, recast on each of 150 raiders it landed on and the
    /// casting queue grew until the server stopped (35 GB). A monster's instant spell is not asked for again on the same target
    /// within a second, nor queued twice, and a monster keeps at most 16 requests.
    /// </summary>
    [TestFixture]
    public class UT_NpcRecastGuard
    {
        private static bool Blocked(bool instant = true, int spell = 11822, int target = 7, int lastSpell = 11822, int lastTarget = 7,
            long last = 10_000, long now = 10_050, int pending = 0, bool duplicate = false) =>
            CastingComponent.NpcRecastBlocked(instant, spell, target, lastSpell, lastTarget, last, now, pending, duplicate);

        [Test]
        public void TheChainIsCut() => Assert.Multiple(() =>
        {
            Assert.That(Blocked(), Is.True, "the same instant spell on the same target in the same moment");
            Assert.That(Blocked(duplicate: true, now: 20_000), Is.True, "the same spell and target already waiting");
            Assert.That(Blocked(pending: CastingComponent.MaxNpcPendingRequests, spell: 1, now: 20_000), Is.True, "a full queue");
        });

        [Test]
        public void OrdinaryCastsGoAhead() => Assert.Multiple(() =>
        {
            Assert.That(Blocked(now: 10_000 + CastingComponent.NpcInstantRecastGapMs), Is.False, "the next melee swing a few seconds on");
            Assert.That(Blocked(target: 8), Is.False, "the same spell on another target (scripts that cast at each player in turn)");
            Assert.That(Blocked(spell: 11821), Is.False, "another spell");
            Assert.That(Blocked(instant: false), Is.False, "a spell with a cast time");
        });
    }
}
