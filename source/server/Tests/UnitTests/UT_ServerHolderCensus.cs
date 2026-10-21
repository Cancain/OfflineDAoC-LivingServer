using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using DOL.Database;
using DOL.GS;
using DOL.GS.ServerRules;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>SERVER_HOLDER_CENSUS: which field path still holds NPCs that left the world (overnight run, 2026-10-21).</summary>
    [TestFixture]
    public class UT_ServerHolderCensus
    {
        private sealed class Server : GameServer
        {
            protected override IServerRules ServerRulesImpl => new NormalServerRules();
            protected override IObjectDatabase DataBaseImpl => EmptyDb;
        }
        private static readonly IObjectDatabase EmptyDb =
            DispatchProxy.Create<IObjectDatabase, UT_AutonomousBotRealmPointRewards.EmptyReadDatabase>();
        private GameServer _previous;

        [SetUp]
        public void SetUp()
        {
            _previous = GameServer.Instance;
            GameServer.LoadTestDouble((Server)RuntimeHelpers.GetUninitializedObject(typeof(Server)));
        }

        [TearDown]
        public void TearDown() => GameServer.LoadTestDouble(_previous);

        private sealed class Party { public List<object> Members = new(); }
        private sealed class Registry { public Dictionary<int, Party> Parties = new(); public object[] Recent = new object[4]; }

        private static GameNPC Npc() => (GameNPC)RuntimeHelpers.GetUninitializedObject(typeof(GameNPC));

        [Test]
        public void AHeldNpcIsReportedWithThePathThatHoldsIt()
        {
            GameNPC held = Npc(), recent = Npc(), free = Npc();
            var registry = new Registry();
            registry.Parties[7] = new Party { Members = { "not a target", held } };
            registry.Recent[2] = recent;
            var result = ServerHolderCensus.Scan([("Raids.Registry", registry, true)], [held, recent, free]);
            Assert.Multiple(() =>
            {
                Assert.That(result.Targets, Is.EqualTo(3));
                Assert.That(result.Reached, Is.EqualTo(2), "the free NPC is held by nothing scanned");
                var paths = result.Holders.Select(h => h.Path).ToArray();
                Assert.That(paths, Has.Some.StartsWith("Raids.Registry.Parties").And.Some.Contains("Members"));
                Assert.That(paths, Has.Some.EqualTo("Raids.Registry.Recent[]"));
                Assert.That(result.Holders.Sum(h => h.Count), Is.EqualTo(2));
                Assert.That(result.Holders.All(h => h.Types == "GameNPC:1"), Is.True);
            });
        }

        [Test]
        public void GameObjectsAreLeaves()
        {
            GameNPC target = Npc();
            GameNPC activeRoot = Npc();
            var result = ServerHolderCensus.Scan([("Static.Npc", activeRoot, true), ("Static.Target", target, true)], [target]);
            Assert.That(result.Reached, Is.EqualTo(1));
            Assert.That(result.Holders.Single().Path, Is.EqualTo("Static.Target"));
        }

        [Test]
        public void CyclesAreWalkedOnce()
        {
            var a = new List<object>();
            var b = new List<object> { a };
            a.Add(b);
            GameNPC target = Npc();
            b.Add(target);
            var result = ServerHolderCensus.Scan([("Static.A", a, true)], [target]);
            Assert.That(result.Reached, Is.EqualTo(1));
            Assert.That(result.OutOfBudget, Is.False);
        }
    }
}
