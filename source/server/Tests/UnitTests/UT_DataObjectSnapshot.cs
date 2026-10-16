using System.Reflection;
using DOL.Database;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Heap dump 2026-10-15: each save's dirty-tracking snapshot kept the snapshot before it, so every saved object held all
    /// its past versions and the live heap grew for as long as the server ran.
    /// </summary>
    [TestFixture]
    public class UT_DataObjectSnapshot
    {
        private static readonly FieldInfo Snapshot = typeof(DataObject).GetField("_snapshot", BindingFlags.Instance | BindingFlags.NonPublic);

        [Test]
        public void RepeatedSnapshotsKeepOnlyTheLatest()
        {
            var spell = new DbSpell { Name = "first" };
            spell.TakeSnapshot();
            spell.Name = "second";
            spell.TakeSnapshot();
            spell.Name = "third";
            spell.TakeSnapshot();

            var latest = (DataObject)Snapshot.GetValue(spell);
            Assert.That(((DbSpell)latest).Name, Is.EqualTo("third"));
            Assert.That(Snapshot.GetValue(latest), Is.Null);
        }

        [Test]
        public void CloneStartsWithoutSnapshot()
        {
            var spell = new DbSpell { Name = "saved" };
            spell.TakeSnapshot();
            Assert.That(Snapshot.GetValue(spell.Clone()), Is.Null);
        }
    }
}
