using System.Linq;
using System.Reflection;
using DOL.GS;
using DOL.GS.ServerProperties;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Owner 2026-10-15: a player with seven companion bots and no other gamebots must be able to take a relic from an
    /// enemy pad (players could never take one: companions did not count and sixteen were required).
    /// </summary>
    [TestFixture]
    public class UT_RelicPadAttackers
    {
        private static int RequiredDefault() =>
            (int)typeof(Properties).GetField(nameof(Properties.RELIC_PLAYERS_REQUIRED_ON_PAD))
                .GetCustomAttribute<ServerPropertyAttribute>().DefaultValue;

        [Test]
        public void PlayerAndSevenCompanionsAreEnough()
        {
            const eRealm pad = eRealm.Hibernia;
            int count = (GameRelicPad.CountsOnPad(pad, eRealm.Midgard, true, false, true) ? 1 : 0) +   // the player
                        Enumerable.Range(0, 7).Count(_ => GameRelicPad.CountsOnPad(pad, eRealm.Midgard, true, false, true)); // companions
            Assert.That(RequiredDefault(), Is.EqualTo(8));
            Assert.That(count, Is.GreaterThanOrEqualTo(RequiredDefault()));
        }

        [Test]
        public void OnlyLivingVisibleEnemiesCount()
        {
            Assert.That(GameRelicPad.CountsOnPad(eRealm.Hibernia, eRealm.Hibernia, true, false, true), Is.False);  // own realm
            Assert.That(GameRelicPad.CountsOnPad(eRealm.Hibernia, eRealm.Midgard, false, false, true), Is.False);  // dead
            Assert.That(GameRelicPad.CountsOnPad(eRealm.Hibernia, eRealm.Midgard, true, true, true), Is.False);    // stealthed
            Assert.That(GameRelicPad.CountsOnPad(eRealm.Hibernia, eRealm.Midgard, true, false, false), Is.False);  // not a player/gamebot/companion
            Assert.That(GameRelicPad.CountsOnPad(eRealm.Hibernia, eRealm.None, true, false, true), Is.False);      // realmless
        }
    }
}
