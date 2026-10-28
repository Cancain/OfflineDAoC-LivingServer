using System.Linq;
using System.Reflection;
using DOL.GS.Keeps;
using DOL.GS.ServerProperties;
using NUnit.Framework;

namespace DOL.UnitTests
{
    // Fork: battleground keep claims (ForkKeepClaims). Every switch is off by default, and off means upstream's rules.
    [TestFixture]
    public class UT_ForkKeepClaims
    {
        [TestCase(true, true, false, false, true)]
        [TestCase(false, true, false, false, false)]   // switched off: upstream's BaseLevel rule decides
        [TestCase(true, true, true, false, false)]     // a portal keep, never
        [TestCase(true, true, false, true, false)]     // a relic keep, never
        [TestCase(true, false, false, false, false)]   // not a battleground region
        public void BattlegroundKeep_IsClaimableOnlyWhenSwitchedOnAndNoPortalOrRelicKeep(bool enabled, bool battleground, bool portal, bool relic, bool claimable)
        {
            Assert.That(ForkKeepClaims.IsClaimableBattlegroundKeep(enabled, battleground, portal, relic), Is.EqualTo(claimable));
        }

        [TestCase(true, true, true, true)]
        [TestCase(true, false, true, false)]   // unclaimed: levels change as upstream
        [TestCase(true, true, false, false)]   // a frontier keep: as upstream
        [TestCase(false, true, true, false)]   // switched off
        public void ClaimedBattlegroundKeep_KeepsItsLevel(bool enabled, bool claimed, bool battleground, bool holds)
        {
            Assert.That(ForkKeepClaims.HoldsLevel(enabled, claimed, battleground), Is.EqualTo(holds));
        }

        [TestCase(true, true, (byte)1, (byte)1)]    // a released battleground keep keeps the level it had before the claim
        [TestCase(true, false, (byte)5, (byte)4)]   // a frontier keep: starting_keep_level, as upstream
        [TestCase(false, true, (byte)1, (byte)4)]   // switched off: as upstream
        public void ReleasedBattlegroundKeep_KeepsItsLevel(bool enabled, bool battleground, byte current, byte expected)
        {
            Assert.That(ForkKeepClaims.ReleaseLevel(enabled, battleground, current, startingLevel: 4), Is.EqualTo(expected));
        }

        [Test]
        public void GroupBots_CountOnlyWhenSwitchedOnAliveAndInTheKeepArea()
        {
            ForkKeepClaims.BotPresence[] bots =
            [
                new(Alive: true, InArea: true),
                new(Alive: true, InArea: true),
                new(Alive: false, InArea: true),
                new(Alive: true, InArea: false),
            ];

            Assert.That(ForkKeepClaims.CountPresent(false, 1, bots), Is.EqualTo(1));
            Assert.That(ForkKeepClaims.CountPresent(true, 1, bots), Is.EqualTo(3));
            Assert.That(ForkKeepClaims.CountPresent(true, 1, null), Is.EqualTo(1));
        }

        [Test]
        public void ClaimCount_SwitchedOnCountsOnlyTheSameKind()
        {
            bool[] claimedAreBattleground = [true, false, false];

            Assert.That(ForkKeepClaims.ClaimCount(false, true, claimedAreBattleground), Is.EqualTo(3), "off: every claim, as upstream");
            Assert.That(ForkKeepClaims.ClaimCount(true, true, claimedAreBattleground), Is.EqualTo(1));
            Assert.That(ForkKeepClaims.ClaimCount(true, false, claimedAreBattleground), Is.EqualTo(2));
            Assert.That(ForkKeepClaims.ClaimCount(true, true, null), Is.EqualTo(0));
        }

        [TestCase(false, 1, 0, null)]
        [TestCase(false, 1, 1, "Your guild already owns a keep.")]
        [TestCase(true, 1, 1, "Your guild already owns a battleground keep.")]
        [TestCase(false, 0, 0, "Keep claiming is disabled!")]
        [TestCase(true, 0, 0, "Battleground keep claiming is disabled!")]
        [TestCase(false, 3, 2, null)]
        [TestCase(false, 3, 3, "Your guild already owns the limit of keeps (3)")]
        [TestCase(true, 2, 2, "Your guild already owns the limit of battleground keeps (2)")]
        public void ClaimLimitRefusal_FollowsUpstreamsRules(bool battleground, int limit, int claimed, string refusal)
        {
            Assert.That(ForkKeepClaims.ClaimLimitRefusal(battleground, limit, claimed), Is.EqualTo(refusal));
        }

        [Test]
        public void SeparateLimits_ABattlegroundClaimDoesNotBlockTheFrontierOrTheOtherWayRound()
        {
            // A guild with one frontier keep; guilds_claim_limit 1, fork_bg_claim_limit 1.
            bool[] claimed = [false];

            Assert.That(Refusal(true, battleground: true, claimed), Is.Null, "on: the battleground keep may still be claimed");
            Assert.That(Refusal(true, battleground: false, claimed), Is.EqualTo("Your guild already owns a keep."));
            Assert.That(Refusal(false, battleground: true, claimed), Is.EqualTo("Your guild already owns a keep."), "off: one keep in all, as upstream");

            // A guild with one battleground keep.
            claimed = [true];
            Assert.That(Refusal(true, battleground: false, claimed), Is.Null, "on: the frontier keep may still be claimed");
            Assert.That(Refusal(true, battleground: true, claimed), Is.EqualTo("Your guild already owns a battleground keep."));

            // Off, upstream's switch answers, in its frontier words, for every keep.
            static string Refusal(bool enabled, bool battleground, bool[] claimed) =>
                ForkKeepClaims.ClaimLimitRefusal(enabled && battleground, 1, ForkKeepClaims.ClaimCount(enabled, battleground, claimed));
        }

        [TestCase(nameof(ForkKeepClaims.FORK_BG_CLAIM), "fork_bg_claim", false)]
        [TestCase(nameof(ForkKeepClaims.FORK_CLAIM_COUNTS_GROUP_BOTS), "fork_claim_counts_group_bots", false)]
        [TestCase(nameof(ForkKeepClaims.FORK_BOT_GUILDS_CLAIM_BG), "fork_bot_guilds_claim_bg", false)]
        [TestCase(nameof(ForkKeepClaims.FORK_BG_CLAIM_LIMIT), "fork_bg_claim_limit", 1)]
        public void Settings_AreServerPropertiesWithSafeDefaults(string field, string key, object defaultValue)
        {
            ServerPropertyAttribute attribute = typeof(ForkKeepClaims).GetField(field, BindingFlags.Public | BindingFlags.Static)
                .GetCustomAttributes(typeof(ServerPropertyAttribute), false).Cast<ServerPropertyAttribute>().Single();

            Assert.That(attribute.Key, Is.EqualTo(key));
            Assert.That(attribute.DefaultValue, Is.EqualTo(defaultValue));
        }
    }
}
