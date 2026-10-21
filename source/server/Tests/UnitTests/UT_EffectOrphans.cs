using DOL.GS;
using NUnit.Framework;
using State = DOL.GS.GameObject.eObjectState;

namespace DOL.UnitTests
{
    /// <summary>Census 2026-10-21: effects outlived the NPCs that held or cast them (2,755, growing). They end now.</summary>
    [TestFixture]
    public class UT_EffectOrphans
    {
        [Test]
        public void EffectsOfDeletedNpcsEnd() => Assert.Multiple(() =>
        {
            Assert.That(EffectService.OutlivedItsLiving(State.Deleted, true, false, null, false), Is.True, "a snare on a deleted monster");
            Assert.That(EffectService.OutlivedItsLiving(State.Active, true, true, State.Deleted, true), Is.True, "a deleted pet's pulse");
            Assert.That(EffectService.OutlivedItsLiving(State.Active, true, false, null, false), Is.False, "a live monster");
            Assert.That(EffectService.OutlivedItsLiving(State.Inactive, true, false, null, false), Is.False, "a bot between regions");
            Assert.That(EffectService.OutlivedItsLiving(State.Deleted, false, false, null, false), Is.False, "a player's saved effects");
            Assert.That(EffectService.OutlivedItsLiving(State.Active, false, true, State.Inactive, true), Is.False, "a pet between regions");
        });
    }
}
