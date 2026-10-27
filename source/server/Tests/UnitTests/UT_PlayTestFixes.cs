using NUnit.Framework;

namespace DOL.GS.Tests
{
    /// <summary>Fixes from the 2026-10-27 evening classic-client play test.</summary>
    [TestFixture]
    public class UT_PlayTestFixes
    {
        [Test]
        public void AHorseTicketQuestionWithoutADestinationIsAnswered()
        {
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("where can i buy a horse ticket?", out string answer), Is.True);
            Assert.That(answer, Does.Contain("stable"));
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("how do i get a ticket", out _), Is.True);
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("where is the stable master", out _), Is.True);
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("selling tickets cheap", out _), Is.False, "no question");
            Assert.That(AutonomousChatKnowledge.TryAnswerTicketsInGeneral("where do i level at 20?", out _), Is.False, "not about tickets");
        }
    }
}
