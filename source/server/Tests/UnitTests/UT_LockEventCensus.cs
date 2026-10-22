using System.Threading;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Live run 2026-10-22: Event handles grew about 1,700 an hour after deleted bots were freed. A .NET Lock makes a Windows
    /// event the first time a thread waits for it and keeps it; the census counts which fields hold such Locks.
    /// </summary>
    [TestFixture]
    public class UT_LockEventCensus
    {
        private sealed class Holder
        {
            public readonly Lock Quiet = new();
            public readonly Lock Contended = new();
            public readonly Inner Part = new();
        }

        private sealed class Inner
        {
            public readonly Lock Deep = new();
        }

        private static void Contend(Lock target)
        {
            using var held = new ManualResetEventSlim();
            var thread = new Thread(() => { lock (target) { held.Set(); Thread.Sleep(200); } });
            thread.Start();
            held.Wait();
            lock (target) { }
            thread.Join();
        }

        [Test]
        public void ALockThatHadToWaitIsCountedWithItsEvent()
        {
            var holder = new Holder();
            Assume.That(ServerLockEventCensus.HasWaitEvent(holder.Quiet), Is.Not.Null, "this runtime's Lock keeps a _waitEvent field");
            Contend(holder.Contended);
            Contend(holder.Part.Deep);

            ServerLockEventCensus.Result result = ServerLockEventCensus.Count([holder]);

            Assert.Multiple(() =>
            {
                Assert.That(result.Locks, Is.EqualTo(3));
                Assert.That(result.WithEvent, Is.EqualTo(2));
                Assert.That(result.ByField, Has.Some.Matches<(string Field, int Locks, int WithEvent)>(f => f.Field == "Holder.Contended" && f.WithEvent == 1));
                Assert.That(result.ByField, Has.Some.Matches<(string Field, int Locks, int WithEvent)>(f => f.Field == "Inner.Deep" && f.WithEvent == 1));
                Assert.That(result.ByField, Has.Some.Matches<(string Field, int Locks, int WithEvent)>(f => f.Field == "Holder.Quiet" && f.WithEvent == 0));
            });
        }
    }
}
