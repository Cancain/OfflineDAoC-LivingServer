using System.Numerics;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>Run 13 (2026-10-16): bots ride near-vertical jump links (Caer Sidi's lift: 964 up over 45) instead of walking them.</summary>
    [TestFixture]
    public class UT_VerticalLink
    {
        [Test]
        public void CaerSidiLiftIsVertical() =>
            Assert.That(Pathfinder.IsVerticalLink(EDtPolyFlags.Jump, new Vector3(39026, 31690, 13862), new Vector3(39024, 31645, 14826)), Is.True);

        [Test]
        public void WalkableRampAndShortJumpAreNot()
        {
            Assert.That(Pathfinder.IsVerticalLink(EDtPolyFlags.Walk, new Vector3(0, 0, 0), new Vector3(0, 45, 964)), Is.False);
            Assert.That(Pathfinder.IsVerticalLink(EDtPolyFlags.Jump, new Vector3(0, 0, 0), new Vector3(0, 200, 150)), Is.False);
            Assert.That(Pathfinder.IsVerticalLink(EDtPolyFlags.Jump, new Vector3(0, 0, 0), new Vector3(0, 400, 500)), Is.False);
        }
    }
}
