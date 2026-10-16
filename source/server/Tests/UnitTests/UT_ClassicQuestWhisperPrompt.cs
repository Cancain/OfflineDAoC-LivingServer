using DOL.GS.Quests;
using NUnit.Framework;

namespace DOL.UnitTests
{
    [TestFixture]
    public class UT_ClassicQuestWhisperPrompt
    {
        [Test]
        public void KeepsAnExactLinkAndDropsTheGeneratorNote()
        {
            Assert.That(ClassicQuests.WhisperPrompt("Tell Trefor you [would like to do more treasure hunting]. (whisper: would like to do more treasure hunting)",
                "would like to do more treasure hunting"), Is.EqualTo("Tell Trefor you [would like to do more treasure hunting]."));
        }

        [Test]
        public void RewritesALinkWhoseCaseDiffersToTheExactKeyword()
        {
            // DataQuest compares the whispered text exactly; the link must send the keyword as stored.
            Assert.That(ClassicQuests.WhisperPrompt("Tell Aziliz the gurites [search for treasure of the lost tower of Tir na mBeo].",
                "search for treasure of the lost tower of tir na mbeo"),
                Is.EqualTo("Tell Aziliz the gurites [search for treasure of the lost tower of tir na mbeo]."));
        }

        [Test]
        public void LinksTheKeywordWhereTheTextNamesIt()
        {
            Assert.That(ClassicQuests.WhisperPrompt("Tell Lilib that Alomali sent me.", "Alomali sent me"), Is.EqualTo("Tell Lilib that [Alomali sent me]."));
        }

        [Test]
        public void AppendsTheLinkWhenTheTextDoesNotNameIt()
        {
            Assert.That(ClassicQuests.WhisperPrompt("Speak with Archibald Oakheart.", "Lisreen"), Is.EqualTo("Speak with Archibald Oakheart. [Lisreen]"));
            Assert.That(ClassicQuests.WhisperPrompt("", "Lisreen"), Is.EqualTo("[Lisreen]"));
        }
    }
}
