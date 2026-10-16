using DOL.GS;
using DOL.GS.Spells;
using NUnit.Framework;

namespace DOL.UnitTests
{
    [TestFixture]
    public class UT_CripplingPlague
    {
        [Test]
        public void SlowRampsFromBarelyToAlmostARoot()
        {
            Assert.That(CripplingPlagueECSEffect.SlowAt(0), Is.EqualTo(10));
            Assert.That(CripplingPlagueECSEffect.SlowAt(0.5), Is.EqualTo(52.5));
            Assert.That(CripplingPlagueECSEffect.SlowAt(1), Is.EqualTo(95));
            Assert.That(CripplingPlagueECSEffect.SlowAt(2), Is.EqualTo(95));
        }

        [Test]
        public void ItIsASnareForImmunityAndEffects()
        {
            var spell = new Spell(new DOL.Database.DbSpell { Type = eSpellType.SluaghbinderCripplingPlague.ToString(), Target = "Enemy" }, 0);
            Assert.That(EffectHelper.GetEffectFromSpell(spell), Is.EqualTo(eEffect.MovementSpeedDebuff));
            Assert.That(EffectHelper.GetImmunityEffectFromSpell(spell), Is.EqualTo(eEffect.SnareImmunity));
        }
    }
}
