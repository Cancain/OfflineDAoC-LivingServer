using DOL.AI.Brain;
using DOL.Database;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Owner report 2026-10-15: Necromancer bots did not use the servant's area debuffs on a single target and sent
    /// Billowing Death (a burst around the servant) from far away. Area debuffs are now picked first when the target lacks
    /// them; the burst needs the servant beside the target.
    /// </summary>
    [TestFixture]
    public class UT_NecromancerServantCommands
    {
        private static Spell Payload(string type, int range, int radius) =>
            new(new DbSpell { Type = type, Target = "Enemy", Range = range, Radius = radius, Duration = 60 }, 40);

        [Test]
        public void AreaDebuffsCountAsDebuffs()
        {
            Assert.That(BotBrain.IsServantDebuff(Payload("StrengthConstitutionDebuff", 1500, 350)), Is.True);  // Shroud of Affliction
            Assert.That(BotBrain.IsServantDebuff(Payload("SpeedDecrease", 1500, 350)), Is.True);               // Vortex of Anguish
            Assert.That(BotBrain.IsServantDebuff(Payload("DamageOverTime", 0, 350)), Is.False);               // Billowing Death
            Assert.That(BotBrain.IsServantDebuff(Payload("DirectDamage", 0, 350)), Is.False);                 // Channeled Anger
        }
    }
}
