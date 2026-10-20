using System;
using System.Collections.Generic;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>Fixes from the 600-per-realm overnight run of 2026-10-19/20.</summary>
    [TestFixture]
    public class UT_OvernightRunFixes
    {
        // Contested raids stay; only the realm that landed the final kill wins (Summoner's Hall, 2026-10-20).
        [TestCase(true, eRealm.None, "Boss defeated")]
        [TestCase(false, eRealm.Hibernia, "Beaten to it")]
        [TestCase(true, eRealm.Hibernia, "Boss defeated")]   // credited first; a later rival kill changes nothing
        [TestCase(false, eRealm.None, "Boss defeated")]      // an uncontested kill with no damage record still counts
        public void OnlyTheRealmThatKilledTheFinalBossWins(bool credited, eRealm beatenBy, string outcome) =>
            Assert.That(AutonomousRealmRaid.CompletionOutcome(credited, beatenBy), Is.EqualTo(outcome));

        // Tuscaran Glacier, 2026-10-20: the Birghir muster stayed at 0 for an hour while Suttung killed the raid.
        [TestCase(0L, 60 * 60_000L, false)]                  // never empty
        [TestCase(1L, 19 * 60_000L, false)]
        [TestCase(1L, 20 * 60_000L + 1, true)]
        [TestCase(10 * 60_000L, 25 * 60_000L, false)]
        public void AMusterEmptyForTwentyMinutesIsSetAside(long emptySince, long now, bool unreachable) =>
            Assert.That(RealmRaidDungeonRoute.MusterUnreachable(emptySince, now), Is.EqualTo(unreachable));

        // Marfach Cavern, 2026-10-20: eight-bot parties pulled Black Lady as a corridor blocker.
        [TestCase(false, false, false, true)]   // an ordinary corridor monster is still cleared
        [TestCase(true, false, false, false)]   // an epic monster nobody came for is gone around or passed
        [TestCase(true, true, false, true)]     // the bots' own target
        [TestCase(true, false, true, true)]     // a raid inside its own dungeon fights its encounters
        public void APartyPullsAnEpicOnlyWhenItCameForIt(bool epic, bool ownTarget, bool inOwnRaidDungeon, bool pulls) =>
            Assert.That(AutonomousDungeonPolicy.PullsOnRoute(epic, ownTarget, inOwnRaidDungeon), Is.EqualTo(pulls));

        [Test]
        public void ThreeDeathsInOnePlaceMakeItTheBotsOwnDangerSpot()
        {
            DateTime now = new(2026, 10, 20, 4, 0, 0, DateTimeKind.Utc);
            var deaths = new List<AutonomousRepeatDeathSpots.Death>
            {
                new(200, 368211, 652323, now.AddMinutes(-50)),
                new(200, 367881, 653097, now.AddMinutes(-30)),
            };
            Assert.That(AutonomousRepeatDeathSpots.Spots(deaths, 200, now), Is.Empty, "two deaths are not a pattern yet");

            deaths.Add(new(200, 368177, 652326, now.AddMinutes(-5)));
            var spots = AutonomousRepeatDeathSpots.Spots(deaths, 200, now);
            Assert.That(spots, Has.Count.EqualTo(1));
            Assert.That(spots[0], Is.EqualTo((368177, 652326)), "the latest death marks the spot");
            Assert.Multiple(() =>
            {
                Assert.That(AutonomousRepeatDeathSpots.Spots(deaths, 100, now), Is.Empty, "another region");
                Assert.That(AutonomousRepeatDeathSpots.Spots(deaths, 200, now.AddHours(3)), Is.Empty, "deaths older than three hours are forgotten");
            });

            deaths.Add(new(200, 300000, 600000, now.AddMinutes(-1)));   // far away: not part of the cluster
            Assert.That(AutonomousRepeatDeathSpots.Spots(deaths, 200, now), Has.Count.EqualTo(1));
        }

        [Test]
        public void ABotsOwnSpotsKeepItsCampsAwayAndForgetOtherBots()
        {
            AutonomousRepeatDeathSpots.Clear();
            try
            {
                DateTime now = DateTime.UtcNow;
                for (int i = 0; i < 3; i++)
                    AutonomousRepeatDeathSpots.Record(42, 200, 368200 + i * 50, 652300, now.AddMinutes(-i));
                var spots = AutonomousRepeatDeathSpots.AllSpots(42, now);
                Assert.Multiple(() =>
                {
                    Assert.That(AutonomousRepeatDeathSpots.IsNear(spots, 200, 369000, 652800), Is.True, "a camp beside the spot");
                    Assert.That(AutonomousRepeatDeathSpots.IsNear(spots, 200, 380000, 652300), Is.False, "a camp well away");
                    Assert.That(AutonomousRepeatDeathSpots.AllSpots(43, now), Is.Empty, "another bot's deaths are its own");
                });
            }
            finally { AutonomousRepeatDeathSpots.Clear(); }
        }

        // Blendrake Faste, 2026-10-20: Midgard kept ~80 attacking Caer Sursbrooke while its own keep fell undefended.
        [TestCase(0, 24, 80, 80, 8, true)]      // nobody defending, the attack keeps 72 of 80
        [TestCase(11, 24, 80, 80, 8, true)]     // still under half the defense cap
        [TestCase(12, 24, 80, 80, 8, false)]    // half the cap defends: the attack keeps its army
        [TestCase(0, 24, 44, 80, 8, false)]     // the attack is already down to about half: it stays
        [TestCase(0, 24, 48, 80, 8, true)]      // 40 left of the 80 that marched
        public void AnAttackingWarbandBreaksOffToDefendItsOwnKeep(int defenders, int cap, int attackers, int marched, int size, bool breaks) =>
            Assert.That(RealmEventPolicy.BreaksOffToDefend(defenders, cap, attackers, marched, size), Is.EqualTo(breaks));

        [TestCase(true, 30, true)]
        [TestCase(true, 0, false)]    // a battle opened before its army arrived
        [TestCase(false, 30, false)]  // attackers still marching: the defense musters as before
        public void DefendersGoStraightInOnceTheAttackersAreAtTheKeep(bool battleStarted, int attackersPresent, bool skip) =>
            Assert.That(RealmEventPolicy.DefendersSkipMuster(battleStarted, attackersPresent), Is.EqualTo(skip));

        // Gjalpinulva, 2026-10-20: immune beyond 2,000 from her lair, but her tether is 2,500.
        [TestCase(1237, -2291, true)]    // where Midgard raiders fought and died
        [TestCase(1400, 1400, false)]    // about 1,980: still in the lair
        [TestCase(0, 2001, true)]
        public void ADragonOutsideItsLairIsTreatedAsOutOfTether(int dx, int dy, bool outside) =>
            Assert.That(DragonLairPlacement.IsOutOfLair(dx, dy), Is.EqualTo(outside));

        [Test]
        public void EveryDragonIsImmuneOutsideTheSameLairRadius() => Assert.Multiple(() =>
        {
            Assert.That(MidGjalpinulva.LairRadius, Is.EqualTo(DragonLairPlacement.LairRadius));
            Assert.That(AlbGolestandt.LairRadius, Is.EqualTo(DragonLairPlacement.LairRadius));
            Assert.That(HibCuuldurach.LairRadius, Is.EqualTo(DragonLairPlacement.LairRadius));
        });

        // Sheeroe Hills, 2026-10-20: the release bind was about 2,300 units from the glimmer pack that killed the bot.
        [TestCase(369726, 651032, false)]   // the bind they kept releasing to
        [TestCase(380000, 651032, true)]    // a bind about 12,000 away
        public void ABotThatKeepsDyingReleasesToABindWellAway(int bindX, int bindY, bool clear) =>
            Assert.That(BotReleaseBindPoints.ClearOf(bindX, bindY, new List<(int X, int Y)> { (368010, 652514) },
                GameBot.ReleaseClearanceFromDeathSpot), Is.EqualTo(clear));

        // Aegir's Landing, 2026-10-19: level-1 parties were sent to the Shrouded Isles and died to level 18-21 cats.
        [TestCase(eRealm.Midgard, (ushort)151, 1, false)]
        [TestCase(eRealm.Midgard, (ushort)151, 9, false)]
        [TestCase(eRealm.Midgard, (ushort)151, 10, true)]
        [TestCase(eRealm.Albion, (ushort)51, 5, false)]
        [TestCase(eRealm.Hibernia, (ushort)181, 5, false)]
        [TestCase(eRealm.Midgard, (ushort)100, 1, true)]     // classic Midgard is where new bots level
        public void NewBotsLevelInTheClassicZonesFirst(eRealm realm, ushort region, int level, bool allowed) =>
            Assert.That(AutonomousOrdinaryPveRealmPolicy.CanAssignCamp(realm, region, 0, level), Is.EqualTo(allowed));
    }
}
