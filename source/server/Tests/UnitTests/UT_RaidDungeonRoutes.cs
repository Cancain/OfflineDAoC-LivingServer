using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>The other raid dungeons (2026-10-20): every one has a hub, a final room and its scripted final bosses.</summary>
    [TestFixture]
    public class UT_RaidDungeons
    {
        [Test]
        public void EveryRaidDungeonIsScheduledWithAHubAndAFinalRoom() => Assert.Multiple(() =>
        {
            foreach (var dungeon in AutonomousRealmRaid.RaidDungeons)
            {
                var definition = AutonomousRealmRaid.Definitions.Single(d => d.Id == dungeon.Id);
                Assert.That(definition.IsDungeon, Is.True, dungeon.Name);
                Assert.That(definition.IsNeutral, Is.False, dungeon.Name);
                Assert.That(definition.Trigger, Is.EqualTo(dungeon.Final), dungeon.Name);
                Assert.That(definition.FinalTypes, Does.Contain(dungeon.BossType), dungeon.Name);
                Assert.That(RealmRaidMuster.Hubs.Where(h => h.Event == dungeon.Id), Is.Not.Empty, $"{dungeon.Name} has a muster hub");
                string realm = dungeon.Realm switch { eRealm.Albion => "albion", eRealm.Midgard => "midgard", _ => "hibernia" };
                Assert.That(dungeon.Id, Does.StartWith($"dungeon-{realm}-"));
                Assert.That(AutonomousRealmRaid.SlowRespawnRegions, Does.Contain(dungeon.Region), dungeon.Name);
                foreach (string type in dungeon.Finals)
                    Assert.That(typeof(GameServer).Assembly.GetTypes().Any(t => t.Name == type && typeof(GameNPC).IsAssignableFrom(t)),
                        Is.True, $"{dungeon.Name}: boss script {type}");
            }
            Assert.That(AutonomousRealmRaid.Definitions.Select(d => d.Id), Is.Unique);
            Assert.That(AutonomousRealmRaid.RaidDungeons.Select(d => d.Region), Is.EquivalentTo(new ushort[] { 61, 50, 62, 277, 150, 161, 246, 190, 276 }));
            var crystal = AutonomousRealmRaid.Definitions.Single(d => d.Id == "dungeon-albion-crystal");
            var hub = RealmRaidMuster.Hubs.First(h => h.Event == crystal.Id);
            Assert.That(crystal.Through, Is.EqualTo(50), "Crystal Cave is entered through Avalon City");
            Assert.That(crystal.EntranceHome(hub), Is.EqualTo(51), "it stages outside Avalon City, in the Shrouded Isles");
            var krondon = AutonomousRealmRaid.Definitions.Single(d => d.Id == "dungeon-albion-krondon");
            Assert.That(krondon.EntranceHome(RealmRaidMuster.Hubs.First(h => h.Event == krondon.Id)), Is.EqualTo(0), "Krondon is entered from open ground");
        });

        [Test]
        public void TheEpicDungeonsKeepTheirOwnFinals() => Assert.Multiple(() =>
        {
            Assert.That(AutonomousRealmRaid.Definitions.Single(d => d.Id == "epic-midgard").FinalTypes, Is.EqualTo(new[] { "KingTuscar", "QueenKula" }));
            Assert.That(AutonomousRealmRaid.Definitions.Single(d => d.Id == "darkness-albion").Trigger, Is.EqualTo(RealmRaidNeutralEvents.FinalApproach(249)));
            Assert.That(AutonomousRealmRaid.Definitions.Single(d => d.Id == "dragon-albion").IsDungeon, Is.False);
        });
    }

    /// <summary>
    /// A raid dungeon's route must prove a path from its entrance to its final room (RealmRaidDungeonRoute.TryCreate
    /// does the same at raid start). Needs OFFLINE_DAOC_TEST_DETOUR and OFFLINE_DAOC_NAV_ROOT (with navmesh/zoneNNN.nav).
    /// </summary>
    [TestFixture, NonParallelizable, Explicit("Needs the native Detour library and installed navmeshes")]
    public class UT_RaidDungeonRoutesProbe
    {
        private string _prior;
        private readonly List<Zone> _loaded = new();

        [SetUp]
        public void Load()
        {
            string root = Environment.GetEnvironmentVariable("OFFLINE_DAOC_NAV_ROOT");
            string native = Environment.GetEnvironmentVariable("OFFLINE_DAOC_TEST_DETOUR");
            Assert.That(root, Is.Not.Null.And.Not.Empty);
            Assert.That(native, Is.Not.Null.And.Not.Empty);
            try
            {
                NativeLibrary.SetDllImportResolver(typeof(LocalPathfindingMgr).Assembly,
                    (name, assembly, search) => name == "lib/Detour" ? NativeLibrary.Load(native) : IntPtr.Zero);
            }
            catch (InvalidOperationException) { }
            _prior = Environment.CurrentDirectory;
            Environment.CurrentDirectory = root;
        }

        [TearDown]
        public void Unload()
        {
            foreach (Zone zone in _loaded) LocalPathfindingMgr.UnloadNavMesh(zone);
            _loaded.Clear();
            Environment.CurrentDirectory = _prior;
        }

        // region, the entrance's arrival point inside (its zone point's target)
        [TestCase(61, 33013, 31379, 15698)]     // Krondon
        [TestCase(50, 32366, 21177, 8071)]      // Avalon City (Albion-only entrance)
        [TestCase(50, 31159, 47380, 8307)]      // Avalon City
        [TestCase(62, 28621, 31142, 16418)]     // Crystal Cave, from its entrance out of Avalon City
        [TestCase(277, 32395, 31847, 16158)]    // Hall of the Corrupt
        [TestCase(150, 28284, 47911, 16000)]    // Trollheim
        [TestCase(161, 34991, 37707, 17231)]    // Iarnvidiur's Lair
        [TestCase(246, 32259, 30624, 16045)]    // Dodens Gruva
        [TestCase(190, 38038, 27675, 13247)]    // Tur Suil
        [TestCase(276, 32915, 29238, 16268)]    // Marfach Caverns
        [TestCase(191, 32072, 29524, 17051)]    // control: Galladoria
        [TestCase(160, 35612, 17899, 19050)]    // control: Tuscaran Glacier
        public void TheFinalRoomIsReachableFromTheEntrance(int regionId, int x, int y, int z) =>
            Reach(regionId, new(x, y, z), AutonomousRealmRaid.Definitions.First(d => d.Region == regionId).Trigger);

        // The Crystal Cave raid walks through Avalon City: from each entrance to the Crystal Cave portal.
        [TestCase(32366, 21177, 8071)]
        [TestCase(31159, 47380, 8307)]
        public void AvalonCityLeadsToTheCrystalCavePortal(int x, int y, int z) => Reach(50, new(x, y, z), new(21094, 42184, 7909));

        // Krondon, 2026-10-21: by its portal in Aldland only 7 slots in a row had a staging post, and the rally failed.
        [Test]
        public void KrondonsPortalHasRoomForItsRaid()
        {
            var region = (Region)RuntimeHelpers.GetUninitializedObject(typeof(Region));
            var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
            typeof(Region).GetField("m_regionData", flags).SetValue(region, new RegionData { Id = 51 });
            var zones = new List<Zone>();
            typeof(Region).GetField("m_zones", flags).SetValue(region, zones);
            var zone = new Zone(region, 56, "Aldland", 44 * 8192, 58 * 8192, 65536, 65536, 56, false, 0, false, 0, 0, 0, 0, 0);
            zones.Add(zone);
            _loaded.Add(zone);
            LocalPathfindingMgr.LoadNavMesh(zone);
            var nav = PathfindingProvider.LocalPathfindingMgr;
            Assert.That(nav.HasNavmesh(zone), Is.True, "zone056.nav loaded");
            var posts = new List<Vector3>();
            for (int slot = 0; slot < RealmRaidRecruitmentPolicy.MaximumParties; slot++)
                if (RealmRaidStaging.TryDungeonPost(nav, zone, new(386927, 479721, 3664), slot, posts, out Vector3 post))
                    posts.Add(post);
            TestContext.Out.WriteLine($"Krondon staging posts: {posts.Count}");
            // Krondon raids up to 160: twenty eight-bot parties.
            Assert.That(posts.Count, Is.GreaterThanOrEqualTo(20));
        }

        private void Reach(int regionId, Vector3 entrance, Vector3 trigger)
        {
            int x = (int)entrance.X, y = (int)entrance.Y, z = (int)entrance.Z;
            var region = (Region)RuntimeHelpers.GetUninitializedObject(typeof(Region));
            typeof(Region).GetField("m_regionData", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                .SetValue(region, new RegionData { Id = (ushort)regionId });
            typeof(Region).GetField("m_zones", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                .SetValue(region, new List<Zone>());
            var zone = new Zone(region, (ushort)regionId, $"zone {regionId}", 8192, 8192, 65536, 65536, (ushort)regionId, false, 0, false, 0, 0, 0, 0, 0);
            ((List<Zone>)typeof(Region).GetField("m_zones", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                .GetValue(region)).Add(zone);
            _loaded.Add(zone);
            LocalPathfindingMgr.LoadNavMesh(zone);
            var nav = PathfindingProvider.LocalPathfindingMgr;
            Assert.That(nav.HasNavmesh(zone), Is.True, "navmesh loaded");
            Vector3? floor = nav.GetClosestPoint(zone, new(x, y, z), 48, 48, 64, nav.DefaultFilters);
            Assert.That(floor.HasValue, Is.True, "navmesh floor at the entrance arrival");
            Assert.That(AutonomousRendezvousNavigation.HasLocalExit(nav, zone, floor.Value), Is.True, "the arrival has a way out");
            bool reached = AutonomousZonePointApproach.TryResolve(nav, zone, floor.Value, trigger, 220, out Vector3 approach);
            TestContext.Out.WriteLine($"region {regionId}: entrance {floor.Value} -> final {trigger}: {(reached ? $"reached at {approach}" : "no path")}");
            Assert.That(reached, Is.True, "a proven path from the entrance to the final room");
        }
    }
}
