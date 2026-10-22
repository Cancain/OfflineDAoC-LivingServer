using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Owner, 2026-10-20: native memory grew about 250 MB an hour because a Detour query was kept for every thread and
    /// zone and never freed. Queries are now pooled per zone. Needs the native library and one navmesh:
    /// OFFLINE_DAOC_TEST_DETOUR (libDetour) and OFFLINE_DAOC_NAV_ROOT (a folder holding navmesh/zone021.nav).
    /// </summary>
    [TestFixture, NonParallelizable, Explicit("Needs the native Detour library and an installed navmesh")]
    public class UT_NavQueryPool
    {
        private string _prior;
        private Zone _zone;

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
            catch (InvalidOperationException) { } // resolver already set by an earlier test
            _prior = Environment.CurrentDirectory;
            Environment.CurrentDirectory = root;
            var region = (Region)RuntimeHelpers.GetUninitializedObject(typeof(Region));
            _zone = new Zone(region, 21, "Tomb of Mithra", 0, 0, 65536, 65536, 21, false, 0, false, 0, 0, 0, 0, 0);
            LocalPathfindingMgr.LoadNavMesh(_zone);
            Assert.That(new LocalPathfindingMgr().HasNavmesh(_zone), Is.True, "zone021.nav loaded");
        }

        [TearDown]
        public void Unload()
        {
            if (_zone != null) LocalPathfindingMgr.UnloadNavMesh(_zone);
            Environment.CurrentDirectory = _prior;
        }

        private void Query(LocalPathfindingMgr pathing, int calls)
        {
            for (int i = 0; i < calls; i++)
                pathing.GetClosestPoint(_zone, new Vector3(32768 + i, 32768, 0), 512, 512, 512, pathing.DefaultFilters);
        }

        [Test]
        public void ThreadsThatComeAndGoShareTheZonesQueries()
        {
            var pathing = new LocalPathfindingMgr();
            long liveBefore = LocalPathfindingMgr.LiveQueries, madeBefore = LocalPathfindingMgr.QueriesCreated;

            // 200 short-lived threads, one after another, as .NET pool threads come and go.
            for (int i = 0; i < 200; i++)
            {
                var thread = new Thread(() => Query(pathing, 20));
                thread.Start();
                thread.Join();
            }
            Assert.That(LocalPathfindingMgr.QueriesCreated - madeBefore, Is.EqualTo(1), "one query, reused by every thread");
            Assert.That(LocalPathfindingMgr.LiveQueries - liveBefore, Is.EqualTo(1));

            // 32 threads at once: at most one query each while they run, and no more than the idle limit kept after.
            using var start = new ManualResetEventSlim();
            var threads = Enumerable.Range(0, 32).Select(_ => new Thread(() => { start.Wait(); Query(pathing, 2_000); })).ToList();
            threads.ForEach(t => t.Start());
            start.Set();
            threads.ForEach(t => t.Join());
            long kept = LocalPathfindingMgr.LiveQueries - liveBefore;
            Assert.That(kept, Is.InRange(1, Math.Max(4, Environment.ProcessorCount)));
            Assert.That(LocalPathfindingMgr.QueriesCreated - madeBefore, Is.LessThanOrEqualTo(33));

            // The zone's navmesh unloaded: every query it had is freed.
            LocalPathfindingMgr.UnloadNavMesh(_zone);
            Assert.That(LocalPathfindingMgr.LiveQueries, Is.EqualTo(liveBefore));
            _zone = null;
        }
    }
}
