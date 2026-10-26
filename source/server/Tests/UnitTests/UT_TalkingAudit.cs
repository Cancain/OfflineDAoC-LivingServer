using System;
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;

namespace DOL.GS.Tests
{
    /// <summary>
    /// The talking update audit (2026-10-26): 320 realistic player lines (Data/chat_audit_player_lines.json, written blind to the
    /// code, each labelled with what a sensible player would expect back) and how the reply path reads them. Before the audit
    /// 149 of 320 (47%) were read the way the label wants, after it 307 (96%). Fresh sets written blind afterwards were read
    /// right only 62-65% of the time on their first run, so these rates are what the fixes were made against, not what new
    /// chat gets (docs/bot-voices/TALKING-UPDATE.md). Two of those sets (chat_audit_holdout_lines.json) were then fixed against
    /// too and are kept here; tools/bot-voices/eval/fresh_lines_3.json is the third, untuned. The floors keep fixes from sliding back.
    /// </summary>
    [TestFixture]
    public class UT_TalkingAudit
    {
        /// <summary>The share of lines read as their label wants (measured 2026-10-26 after the fixes; see the test output).</summary>
        public const double Floor = 0.93;

        [Test]
        public void TheAuditLinesAreReadTheWayAPlayerExpects()
        {
            ChatAuditRoute.Item[] items = ChatAuditRoute.Load();
            Assert.That(items.Length, Is.EqualTo(320));
            var misses = new List<string>();
            foreach (ChatAuditRoute.Item item in items)
            {
                (string path, _) = ChatAuditRoute.Route(item, new Random(1));
                if (!ChatAuditRoute.Fits(item.expect, path))
                    misses.Add($"[{item.channel}] {item.text} | expect {item.expect} | got {path}");
            }
            double rate = 1.0 - (double)misses.Count / items.Length;
            TestContext.Out.WriteLine($"read as expected: {rate:P1} ({items.Length - misses.Count}/{items.Length})");
            foreach (string miss in misses)
                TestContext.Out.WriteLine("  " + miss);
            Assert.That(rate, Is.GreaterThanOrEqualTo(Floor), string.Join("\n", misses));
        }

        /// <summary>The two holdout sets, fixed against after their first runs (61.9% and 65.0%).</summary>
        public const double HoldoutFloor = 0.92;

        [Test]
        public void TheHoldoutLinesAreReadTheWayAPlayerExpects()
        {
            ChatAuditRoute.Item[] items = ChatAuditRoute.Load("chat_audit_holdout_lines.json");
            Assert.That(items.Length, Is.EqualTo(320));
            var misses = new List<string>();
            foreach (ChatAuditRoute.Item item in items)
            {
                (string path, _) = ChatAuditRoute.Route(item, new Random(1));
                if (!ChatAuditRoute.Fits(item.expect, path))
                    misses.Add($"[{item.channel}] {item.text} | expect {item.expect} | got {path}");
            }
            double rate = 1.0 - (double)misses.Count / items.Length;
            TestContext.Out.WriteLine($"read as expected: {rate:P1} ({items.Length - misses.Count}/{items.Length})");
            foreach (string miss in misses)
                TestContext.Out.WriteLine("  " + miss);
            Assert.That(rate, Is.GreaterThanOrEqualTo(HoldoutFloor), string.Join("\n", misses));
        }

        [TestCase("torvald u still a thane?", "torvald", "fact class")]
        [TestCase("u r a healer siobhan?", "siobhan", "fact class")]
        [TestCase("nessa whered u get that cloak", "nessa", "fact gear")]
        [TestCase("hey Aeloria what class is that", "Aeloria", "fact class")]
        public void ABotsOwnNameIsNotPartOfTheQuestion(string text, string to, string path) =>
            Assert.That(ChatAuditRoute.Route(new ChatAuditRoute.Item(text, "say", null, "", "", to), new Random(1)).Path, Is.EqualTo(path));

        [TestCase("x", "lfm vendo caverns need a tank pst", "join")]
        [TestCase("me", "anyone want to come with to lough derg?", "join")]
        [TestCase("ty ty", "gz on the ding!", "none thanked")]
        [TestCase("o ya what stats", "found a nice sword in spindelhalla", "thread followup_detail")]
        [TestCase("really? whered they go", "the zerg just left emain", "thread followup_whereto")]
        [TestCase("into what", "just respecced lol", "thread followup_specific")]
        public void AReplyToTheBotsLastLineIsReadInThread(string text, string context, string path) =>
            Assert.That(ChatAuditRoute.Route(new ChatAuditRoute.Item(text, "faction", context, "", ""), new Random(1)).Path, Is.EqualTo(path));

        [Test]
        public void GearPlansAndBusyAnswersComeFromTheBot()
        {
            var r = new Random(2);
            var bare = new AutonomousChatQuestions.BotFacts(1, 20, "Thane", eRealm.Midgard, 0, BotPersonalityType.Leveler, false, 0, null, 0, 0);
            Assert.That(AutonomousChatQuestions.AnswerSelf("gear", "nice armor where from", bare, r), Does.Contain("gear").Or.Contains("any"));
            var crafted = bare with { Equipped = 8, Crafted = 6 };
            Assert.That(AutonomousChatQuestions.AnswerSelf("gear", "whered u get that armor", crafted, r), Does.Contain("craft"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("plans", "u goin to emain later", bare, r), Does.Contain("level"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("busy", "u busy", bare with { Busy = true }, r), Does.Contain("busy").Or.Contains("middle"));
        }

        // Each of these was read wrong before the audit; the comment says what it drew.
        [TestCase("is thid open for lvl 21", "faction", "fact world")]                 // "if you see the zerg coming, call it out"
        [TestCase("what lvl for vendo caverns", "faction", "fact world")]              // "bring a group the pulls stack"
        [TestCase("r u 50 yet", "tell", "fact level")]                                 // nothing
        [TestCase("are u a healer", "tell", "fact class")]                             // "healers have mez too ppl forget"
        [TestCase("can lurikeens be wardens", "faction", "not sure")]                  // "every class thinks they are the gimped one"
        [TestCase("inventory full, gonna run to the merchant brb", "group", "intent away")] // a trade remark
        [TestCase("anyone know if alchemy is decent inc these days", "faction", "shape ask_opinion")] // "How many and where?"
        [TestCase("necro or cab for pve", "faction", "shape ask_choice")]              // class remarks
        [TestCase("need a hand with that?", "say", "shape player_offer")]              // "how many are you? i can fill a spot"
        [TestCase("are pbae groups worth it for xp", "faction", "shape ask_opinion")]  // "thane here, where are u? invite me"
        [TestCase("my old group quit the game, kinda lonely now", "guild", "shape complaint")] // offers to join
        [TestCase("finished my epic quest finally", "guild", "shape player_goodnews")] // nothing
        [TestCase("back from dinner", "guild", "intent back")]                         // nothing
        [TestCase("stealthers near the dock watch out", "faction", "shape player_headsup")] // "If you see the zerg coming, call it out."
        [TestCase("adds!!", "group", "group warning")]                                 // nothing
        [TestCase("dont rez me yet adds still up", "group", "shape player_wait")]      // "wish i could, no rez spell"
        [TestCase("hey u human", "tell", "intent botcheck")]                           // a greeting
        [TestCase("worst healer ever", "group", "intent abuse")]                       // class remarks
        [TestCase("its 3am and i have class at 8", "guild", "shape player_rl_late")]   // class remarks
        [TestCase("stuck in a rock in the black mountains, help?", "faction", "fact world")] // "Rest after every pull, saves deaths."
        public void ALineTheAuditFoundIsReadRight(string text, string channel, string path) =>
            Assert.That(ChatAuditRoute.Route(new ChatAuditRoute.Item(text, channel, null, "", ""), new Random(1)).Path, Is.EqualTo(path));

        [TestCase("which bridge", "i usually pull at the bridge", "thread followup_which")]
        [TestCase("nice how long did that take u", "just hit 47", "thread followup_howlong")]
        [TestCase("the one by the inn?", "try the horse from cotswold", "thread followup_confirm")]
        [TestCase("y", "i'd skip the barrows for now", "thread followup_why")]
        [TestCase("y", "ready to pull?", "thread answer")]
        [TestCase("32", "what level are you?", "thread answer")]
        [TestCase("no thanks im good", "want some buffs?", "thread decline")]
        [TestCase("sec need pow", "ready?", "thread wait")]
        [TestCase("ty", "theres a stablemaster just inside the gate", "thread thanks")]
        public void AFollowUpOrAnswerFollowsTheBotsLine(string text, string context, string path) =>
            Assert.That(ChatAuditRoute.Route(new ChatAuditRoute.Item(text, "group", context, "", ""), new Random(1)).Path, Is.EqualTo(path));

        [Test]
        public void ClosingsFitTheKindOfAnswer()
        {
            var ready = new ChatThreadLog.Said("c", 1, "B", "ready to pull?", "ask", 0);
            Assert.That(AutonomousChatThreads.ClosingSets(ready, "ya go")[0], Is.EqualTo("ask_yes"));
            Assert.That(AutonomousChatThreads.ClosingSets(ready, "nah not yet")[0], Is.EqualTo("ask_no"));
            var personal = new ChatThreadLog.Said("c", 1, "B", "how long you been playing?", "ask", 0);
            Assert.That(AutonomousChatThreads.ClosingSets(personal, "since beta lol")[0], Is.EqualTo("ask_personal"));
            var where = new ChatThreadLog.Said("c", 1, "B", "anyone know where the bard trainer is?", "ask_where", 0);
            Assert.That(AutonomousChatThreads.ClosingSets(where, "by the bank i think")[0], Is.EqualTo("ask_where"));
        }

        [Test]
        public void ABotAnswersAboutItselfFromWhatIsTrue()
        {
            var r = new Random(3);
            var healer = new AutonomousChatQuestions.BotFacts(7, 50, "Druid", eRealm.Hibernia, 25, BotPersonalityType.Crafter, true, 0, "Tir Guard");
            Assert.That(AutonomousChatQuestions.AnswerSelf("level", "r u 50 yet", healer, r), Does.Contain("50"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("class", "are u a healer", healer, r), Does.StartWith("yep"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("rank", "whats ur rr", healer, r), Does.Contain("3L6"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("speed", "do u have speed", healer, r), Does.Not.Contain("no"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("pots", "u got pots", healer, r), Does.Contain("none").Or.Contains("out"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("guild", "what guild are you in", healer, r), Is.EqualTo("Tir Guard"));
            Assert.That(AutonomousChatQuestions.AnswerSelf("craft", "can u make me a set", healer, r), Does.Not.Contain("not a crafter"));
            Assert.That(AutonomousChatQuestions.RankText(0), Is.EqualTo("1L1"));
            Assert.That(AutonomousChatQuestions.RankText(13), Is.EqualTo("2L4"));
            var thane = ChatAuditRoute.Me;
            Assert.That(AutonomousChatQuestions.CantDo("heal me", thane), Does.StartWith("cant heal"));
            Assert.That(AutonomousChatQuestions.CantDo("pull the next one", thane), Is.Null);
        }

        [Test]
        public void PlaceLevelsComeFromTheWorldData()
        {
            var places = AutonomousChatPlaces.All;
            Assert.That(places.Single(p => p.Key == "thidranki").Levels, Is.EqualTo(new[] { 20, 24 }));
            Assert.That(places.Where(p => p.Type == "dungeon").Count(p => p.Levels != null), Is.GreaterThan(20));
            var r = new Random(1);
            Assert.That(AutonomousChatQuestions.AnswerPlaceLevel("is thid open for lvl 26", eRealm.Midgard, places, r), Does.StartWith("no"));
            Assert.That(AutonomousChatQuestions.AnswerPlaceLevel("is tomb of mithra any good for xp at 30ish", eRealm.Albion, places, r),
                Does.Contain("grey"));
            Assert.That(AutonomousChatQuestions.AnswerPlaceLevel("what lvl is muire tomb", eRealm.Midgard, places, r), Does.StartWith("thats in hibernia"));
            Assert.That(AutonomousChatQuestions.AnswerPlaceLevel("is hadrians wall safe alone at 30", eRealm.Albion, places, r), Is.Null,
                "the frontier's danger is players");
            Assert.That(AutonomousChatQuestions.AnswerWorld("zerg heading for our relic keep", eRealm.Midgard, ChatAuditRoute.World, r), Is.Null,
                "a statement is not a question");
        }

        [Test]
        public void WorldAnswersSayWhoHoldsWhat()
        {
            var r = new Random(1);
            Assert.That(AutonomousChatQuestions.AnswerDarknessFalls("is df ours", eRealm.Hibernia, eRealm.Hibernia, r), Does.Contain("ours").Or.Contains("we have"));
            Assert.That(AutonomousChatQuestions.AnswerDarknessFalls("is df ours", eRealm.Albion, eRealm.Hibernia, r), Does.Contain("hib"));
            Assert.That(AutonomousChatQuestions.AnswerRelics("do we still own our relics", eRealm.Midgard, ChatAuditRoute.World.Relics, r),
                Does.Contain("Relic of Thor"));
            Assert.That(AutonomousChatQuestions.AnswerKeep("who owns benowyc", eRealm.Midgard, ChatAuditRoute.World.Keeps, r), Does.Contain("alb"));
            Assert.That(AutonomousChatQuestions.AnswerKeep("is bledmeer ours", eRealm.Midgard, ChatAuditRoute.World.Keeps, r), Does.Contain("ours").Or.Contains("still"));
        }

        [TestCase("is thid open for lvl 21", true)]
        [TestCase("will pay 20g for heat res jewelry", false)]
        [TestCase("have fun all", false)]
        [TestCase("hi all, anyone know where the cleric trainer is", true)]
        [TestCase("r u 50 yet", true)]
        [TestCase("im off to bed", false)]
        public void AQuestionIsReadWithOrWithoutTheMark(string text, bool question) =>
            Assert.That(AutonomousChatQuestions.IsQuestion(text), Is.EqualTo(question));

        [TestCase("how was your group?", false)]
        [TestCase("my old group quit lol", false)]
        [TestCase("want to group?", true)]
        [TestCase("we need a tank for spindelhalla, want in", true)]
        [TestCase("inv full again", false)]
        [TestCase("are u in a guild", false)]
        [TestCase("ok, u in?", true)]
        public void AGroupRequestByTellIsARequest(string text, bool request) =>
            Assert.That(AutonomousBotChatCoordinator.AsksToJoinGroup(text), Is.EqualTo(request));

        [TestCase(48, 10, true)]
        [TestCase(30, 24, false)]
        [TestCase(12, 30, true)]
        public void ABigLevelGapIsMentioned(int bot, int player, bool mentioned) =>
            Assert.That(AutonomousBotChatCoordinator.LevelGapReply(bot, player, new Random(1)) != null, Is.EqualTo(mentioned));

        [TestCase("lfm vendo need healer pst", "healer")]
        [TestCase("lfm spindel need tank and cc", "tank")]
        [TestCase("lf1m mezzer", "cc")]
        [TestCase("lfg 24 druid", null)]
        public void AGroupsNeededRoleIsRead(string text, string role) =>
            Assert.That(AutonomousChatShortTalk.NeededRole(text), Is.EqualTo(role));
    }
}
