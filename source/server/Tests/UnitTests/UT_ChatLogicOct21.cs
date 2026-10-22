using NUnit.Framework;
using Shapes = DOL.GS.AutonomousChatShortTalk;

namespace DOL.GS.Tests
{
    /// <summary>
    /// Chat audit 2026-10-21 (owner: "responses and the conversations aren't happening correctly or logically"). Sample lines
    /// run through the reply path drew answers that did not answer them; these are the rules that route them now.
    /// </summary>
    [TestFixture]
    public class UT_ChatLogicOct21
    {
        // An acknowledgement draws no answer ("yes" drew "interesting", "sure" drew "lol what", "nice" drew "ouch been there").
        [TestCase("yes")]
        [TestCase("ok")]
        [TestCase("sure")]
        [TestCase("nice")]
        [TestCase("me too")]
        [TestCase("i agree")]
        [TestCase("haha same")]
        [TestCase("sounds good")]
        [TestCase("makes sense")]
        public void AnAcknowledgementIsNotAnswered(string text) => Assert.That(Shapes.QuestionShape(text), Is.EqualTo("ack"));

        [TestCase("ty")]
        [TestCase("ok back")]
        [TestCase("good night")]
        [TestCase("ok?")]
        [TestCase("here")]
        public void ThanksAndQuestionsAreNotAcknowledgements(string text) => Assert.That(Shapes.QuestionShape(text), Is.Not.EqualTo("ack"));

        [TestCase("where is a good place to level at 24?", "ask_hunt")]
        [TestCase("what is a good camp for 24?", "ask_hunt")]
        [TestCase("where should i hunt", "ask_hunt")]
        [TestCase("where are the mids?", "ask_enemy")]
        [TestCase("wheres the zerg", "ask_enemy")]
        [TestCase("how much is a bloodied sword worth?", "ask_price")]
        [TestCase("pc on bloodied sword?", "ask_price")]
        [TestCase("anyone want to do a dungeon?", "ask_anyone")]
        [TestCase("anyone going to the relic raid?", "ask_anyone")]
        [TestCase("who wants to duel", "ask_anyone")]
        [TestCase("whats the best spec for a cleric?", "ask_advice")]
        [TestCase("how do i get money?", "ask_advice")]
        [TestCase("what should i do now?", "ask_advice")]
        [TestCase("can you help me?", "ask_help")]
        [TestCase("is it worth going to the frontier at 24?", "ask_opinion")]
        [TestCase("should i respec?", "ask_opinion")]
        [TestCase("i died again", "complaint")]
        [TestCase("this camp sucks", "complaint")]
        [TestCase("where are you?", "ask_whereyou")]
        [TestCase("is anyone in camelot?", "ask_inplace")]
        [TestCase("any albs near cotswold?", "ask_inplace")]
        [TestCase("smite or rejuv?", "ask_choice")]
        // a group request keeps the grouping replies, which are written for it
        [TestCase("anyone want to group?", null)]
        public void QuestionsAreReadForWhatTheyAsk(string text, string shape) => Assert.That(Shapes.QuestionShape(text), Is.EqualTo(shape));

        [TestCase("is the enchanter pet worth leveling with or just a buffbot?")]
        [TestCase("is friar the most fun class in albion or is it just me?")]
        [TestCase("anyone else level their infil solo or am i doing it wrong?")]
        public void AnOrThatIsNotAChoiceIsNotOne(string text) => Assert.That(Shapes.IsEitherOr(text), Is.False);

        [Test]
        public void ThePlaceAskedAboutIsRead() => Assert.Multiple(() =>
        {
            Assert.That(Shapes.PlaceAsked("is anyone in camelot?"), Is.EqualTo("camelot"));
            Assert.That(Shapes.PlaceAsked("any albs near cotswold?"), Is.EqualTo("cotswold"));
            Assert.That(Shapes.PlaceAsked("anyone at the frontier?"), Is.EqualTo("frontier"));
            Assert.That(Shapes.PlaceAsked("anyone in a group?"), Is.Null);
            Assert.That(Shapes.PlaceAsked("anyone want to group?"), Is.Null);
        });

        [TestCase("really?")]
        [TestCase("why?")]
        [TestCase("what?")]
        public void AFollowUpIsLeftToWhoItWasSaidTo(string text) => Assert.That(Shapes.IsFollowUp(text), Is.True);

        [TestCase("two handed or sword and board on a paladin, what do you think?", "imo yes", false)]
        [TestCase("polearm or two handed?", "the first one", true)]
        [TestCase("anyone selling a staff?", "i would just vendor it", false)]
        [TestCase("anyone selling a staff?", "depends who is buying", false)]
        [TestCase("anyone selling a staff?", "check the exchange first", true)]
        [TestCase("wts bloodied sword", "wts or wtb?", false)]
        [TestCase("how much is a bloodied sword worth?", "how much?", false)]
        [TestCase("lfg 24 cleric", "how many are u? i can fill a spot if u inv", false)]
        [TestCase("lfg 24 cleric", "what camp are you thinking?", true)]
        public void AReplyMustFitWhatWasSaid(string incoming, string reply, bool fits) =>
            Assert.That(Shapes.ReplyFits(incoming, reply), Is.EqualTo(fits));

        [TestCase("ask_anyone", "anyone want to do a dungeon?", "me me me", false)]
        [TestCase("ask_anyone", "anyone want to do a dungeon?", "maybe later", true)]
        [TestCase("ask_price", "how much is it worth?", "seen those go cheap on the exchange", true)]
        [TestCase("ask_price", "how much is it worth?", "not for my class sorry", false)]
        [TestCase("ask_opinion", "is it worth going to the frontier at 24?", "whichever is faster", false)]
        public void AShapedReplyMustFitTheQuestion(string shape, string incoming, string reply, bool fits) =>
            Assert.That(AutonomousBotVoices.ShapedFits(shape, incoming, reply), Is.EqualTo(fits));

        [TestCase("anyone want to group?", true)]
        [TestCase("where is a good place to level?", true)]
        [TestCase("inc at benowyc", true)]
        [TestCase("ok", false)]
        [TestCase("lol", false)]
        public void AQuestionIsNotDroppedByTheReplyCooldown(string text, bool needs) =>
            Assert.That(AutonomousBotChatCoordinator.NeedsAnswer(text), Is.EqualTo(needs));

        // Live check 2026-10-21: "anyone in camelot?" drew "im in Camelot Hills".
        [TestCase("camelot", "Camelot Hills", false)]
        [TestCase("camelot", "City of Camelot", true)]
        [TestCase("black mountains", "Black Mtns. North", false)]
        [TestCase("cotswold", "Camelot Hills", false)]
        [TestCase("lyonesse", "Lyonesse", true)]
        [TestCase("salisbury", "Salisbury Plains", true)]
        public void APlaceIsMatchedForWhatItIs(string place, string zone, bool matches) =>
            Assert.That(AutonomousChatLiveAnswers.PlaceMatches(place, [zone],
                ["City of Camelot", "Camelot Hills", "Salisbury Plains", "Lyonesse", "Black Mtns. North"]), Is.EqualTo(matches));

        [TestCase("Uppland", eRealm.Midgard)]
        [TestCase("Hadrian's Wall", eRealm.Albion)]
        [TestCase("Breifine", eRealm.Hibernia)]
        [TestCase("Thidranki", eRealm.None)]
        public void AFrontierZoneBelongsToItsRealm(string zone, eRealm realm) =>
            Assert.That(AutonomousChatLiveAnswers.FrontierHome(zone), Is.EqualTo(realm));

        [TestCase("good camp for 24?", 30, 24)]
        [TestCase("where should i hunt", 30, 30)]
        [TestCase("where do 35s level", 12, 35)]
        public void TheLevelAskedAboutIsRead(string text, int fallback, int level) =>
            Assert.That(AutonomousChatLiveAnswers.LevelAsked(text, fallback), Is.EqualTo(level));
    }
}
