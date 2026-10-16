using DOL.GS;
using DOL.GS.Keeps;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>Run 14 (2026-10-16): a relic keep's doors 10 and 11 must not read as door 0 and the gate.</summary>
    [TestFixture]
    public class UT_SiegeDoorNumber
    {
        [TestCase(210999901, 1)]
        [TestCase(210999910, 10)]
        [TestCase(210999911, 11)]
        [TestCase(1050102, 2)]
        public void UsesBothDigits(int id, int expected) =>
            Assert.That(AutonomousWorldBotController.SiegeDoorNumber(new GameKeepDoor { DoorId = id }), Is.EqualTo(expected));
    }
}
