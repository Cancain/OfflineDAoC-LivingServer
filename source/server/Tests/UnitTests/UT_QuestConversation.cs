using DOL.GS.Quests;
using NUnit.Framework;

namespace DOL.UnitTests
{
    [TestFixture]
    public class UT_QuestConversation
    {
        [Test]
        public void FirstTurnOfAStagedText()
        {
            Assert.That(ClassicQuests.StartConversation(null, null, "What brings you here? {next}Did you get me the mud?"),
                Is.EqualTo("What brings you here?"));
        }

        [Test]
        public void PlainTextIsSaidWhole()
        {
            Assert.That(ClassicQuests.StartConversation(null, null, "Blessings of the Grove upon you."), Is.EqualTo("Blessings of the Grove upon you."));
        }

        [Test]
        public void NoConversationWithoutAPlayer()
        {
            Assert.That(ClassicQuests.ContinueConversation(null, null), Is.False);
        }
    }
}
