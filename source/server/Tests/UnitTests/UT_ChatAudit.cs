using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;
using Intent = DOL.GS.eAutonomousChatIntent;
using VC = DOL.GS.AutonomousBotVoiceCorpus;

namespace DOL.GS.Tests
{
    /// <summary>
    /// Chat audit (2026-10-21): prints sample exchanges through the real classifier, question shapes, fit filters and
    /// corpus, in the order AutonomousBotChatCoordinator.VoicedReply and ScheduleVoicedBotReplies use them. A reading aid,
    /// not a pass/fail test.
    /// </summary>
    [TestFixture, Explicit("Prints sample chat for reading")]
    public class UT_ChatAudit
    {
        private static VC Load()
        {
            var assembly = typeof(VC).Assembly;
            string Read(string suffix)
            {
                string name = assembly.GetManifestResourceNames().Single(n => n.EndsWith(suffix, StringComparison.Ordinal));
                using Stream stream = assembly.GetManifestResourceStream(name);
                using var reader = new StreamReader(stream);
                return reader.ReadToEnd();
            }
            return VC.Parse(Read("chat.corpus.json"), Read("chat.voices.json"));
        }

        private static readonly Dictionary<string, string> Slots = new(StringComparer.Ordinal)
        {
            ["player"] = "Claudecheck", ["level"] = "24", ["class"] = "cleric", ["zone"] = "Black Mountains South",
            ["camp"] = "the bandit camp", ["dungeon"] = "Tomb of Mithra", ["enemy"] = "mids", ["keep"] = "Caer Benowyc",
            ["frontier"] = "Hadrian's Wall", ["capital"] = "Camelot", ["item"] = "Bloodied Sword", ["target"] = "a bandit",
            ["trainer"] = "the cleric trainer", ["town"] = "Cotswold",
        };

        private static bool Pick(VC corpus, VC.Speaker speaker, Random random, out VC.Picked picked, string intent = null,
            string answers = null, Func<VC.Line, bool> filter = null) =>
            corpus.TryPick(new VC.Request("reply", speaker, Slots, null, DateTime.UtcNow, random)
                { Intent = intent, Answers = answers, Filter = filter }, out picked);

        /// <summary>VoicedReply's order (2026-10-21), without Living Server memory and the rez flags. Null: no reply.</summary>
        private static string Reply(VC corpus, VC.Speaker speaker, string incoming, Random random, out string path)
        {
            Intent value = AutonomousChatIntentModel.Predict(incoming);
            string intent = AutonomousBotVoices.IntentName(value);
            string shape = AutonomousChatShortTalk.QuestionShape(incoming);
            path = $"intent={intent} shape={shape ?? "-"}";
            VC.Picked picked;
            if (shape == "ask_howareyou")
            {
                if (Pick(corpus, speaker, random, out picked, answers: "ask_howareyou")) { path += " via=howareyou"; return picked.Text; }
            }
            else if (shape is "ask_whereyou" or "ask_inplace" or "ask_hunt" or "ask_enemy")
            {
                path += " via=LIVE-WORLD";
                return shape == "ask_inplace" ? "(a bot that is there, or nobody)" : "(answer from the live world)";
            }
            else if (shape == "ask_help" && Pick(corpus, speaker, random, out picked, "help", filter: line => line.Text.TrimEnd().EndsWith('?') ||
                         line.Text.Contains("whats up") || line.Text.Contains("what do")))
            { path += " via=help"; return picked.Text; }
            else if (shape is not (null or "ack" or "ask_help") && Pick(corpus, speaker, random, out picked, answers: shape == "ask_price" ? "trade" : shape,
                         filter: line => AutonomousBotVoices.ShapedFits(shape, incoming, line.Text)))
            {
                path += " via=shape";
                return picked.Text;
            }
            if (shape is "ack" or "ask_inplace" || AutonomousChatShortTalk.IsFollowUp(incoming)) { path += " via=SILENT"; return null; }
            if (value == Intent.Unknown)
            {
                if (incoming.Contains('?') && Pick(corpus, speaker, random, out picked, answers: "ask",
                        filter: line => !line.Text.Contains("trainer") && !line.Text.Contains("guard")))
                { path += " via=not-sure"; return picked.Text; }
                path += " via=SILENT"; return null;
            }
            if (value == Intent.ClassTalk)
            {
                string[] asked = AutonomousChatShortTalk.ClassWordsIn(incoming);
                if (asked.Length > 0 && Pick(corpus, speaker, random, out picked, intent, filter: line =>
                        AutonomousChatShortTalk.ClassWordsIn(line.Text).Any(w => asked.Any(a => AutonomousChatShortTalk.SameClassWord(w, a)))))
                { path += " via=class-asked"; return picked.Text; }
                if (Pick(corpus, speaker, random, out picked, intent, filter: line => !AutonomousChatShortTalk.NamesAClass(line.Text)))
                { path += " via=class-general"; return picked.Text; }
            }
            else if (value == Intent.Greeting)
            {
                if (Pick(corpus, speaker, random, out picked, intent, filter: line => !line.Answers.Contains("ask_howareyou")))
                { path += " via=greeting"; return picked.Text; }
            }
            else if (Pick(corpus, speaker, random, out picked, intent, filter: line => AutonomousChatShortTalk.ReplyFits(incoming, line.Text)))
            {
                path += " via=intent";
                return picked.Text;
            }
            if (incoming.Contains('?') && Pick(corpus, speaker, random, out picked, answers: "ask",
                    filter: line => !line.Text.Contains("trainer") && !line.Text.Contains("guard")))
            { path += " via=not-sure"; return picked.Text; }
            path += " via=SILENT";
            return null;
        }

        [Test]
        public void PlayerLines()
        {
            VC corpus = Load();
            var random = new Random(21);
            var speaker = new VC.Speaker(7, "Ysenorbel", eRealm.Albion, "Cleric", 24, BotPersonalityType.Leveler,
                new HashSet<string> { "solo", "outdoors", "day", "can_rez" });
            string[] lines =
            [
                "hi", "hey all", "how is everyone?", "anyone on?", "lfg 24 cleric", "anyone want to group?", "where is a good place to level at 24?",
                "where do i train?", "anyone know where the cleric trainer is?", "what is a good camp for 24?", "is it worth going to the frontier at 24?",
                "how do i get to Tomb of Mithra?", "whats the best spec for a cleric?", "should i go smite or rejuv?", "is the tomb good xp?",
                "anyone going to the relic raid?", "where are the mids?", "inc at benowyc", "what time is it", "lol", "ty", "gz", "ding 25",
                "anyone selling a staff?", "wts bloodied sword", "how much is a bloodied sword worth?", "i died again", "this camp sucks",
                "brb", "back", "anyone want to do a dungeon?", "what are you up to?", "where to next?", "yes", "no", "ok", "sure",
                "cool", "really?", "what?", "why?", "same", "nice", "i agree", "me too", "haha same", "where are you?", "can you help me?",
                "how do i get money?", "what should i do now?", "is anyone in camelot?", "any albs near cotswold?", "who wants to duel",
                "are you a bot?", "gn all",
            ];
            foreach (string line in lines)
            {
                bool knows = AutonomousChatKnowledge.TryAnswer(eRealm.Albion, line, out string knowledge);
                var replies = new List<string>();
                string path = null;
                for (int i = 0; i < 3; i++)
                    replies.Add(knows ? knowledge : Reply(corpus, speaker with { Id = 7 + i }, line, random, out path) ?? "(no reply)");
                TestContext.Out.WriteLine($"PLAYER \"{line}\"  [{(knows ? "KNOWLEDGE" : path)}]");
                foreach (string reply in replies.Distinct())
                    TestContext.Out.WriteLine($"    -> {reply}");
            }
        }

        [Test]
        public void BotOpeners()
        {
            VC corpus = Load();
            var random = new Random(7);
            var speaker = new VC.Speaker(9, "Haroorren", eRealm.Albion, "Mercenary", 24, BotPersonalityType.Leveler,
                new HashSet<string> { "solo", "outdoors", "day" });
            var openers = corpus.Lines.Where(line => line.Kind is "ambient" or "lfg" or "trade" or "rvr" && line.Invites is { Length: > 0 } and not "none")
                .OrderBy(_ => random.Next()).Take(60)
                .Concat(corpus.Lines.Where(line => line.Kind is "ambient" or "rvr" && (line.Text.Contains(" or ") && line.Text.Contains('?') || line.Text.Contains("ram on") || line.Text.Contains("8man")))).ToList();
            int dangling = 0, total = 0;
            foreach (VC.Line opener in openers)
            {
                string text = System.Text.RegularExpressions.Regex.Replace(opener.Text, @"\{(\w+)\}", m => Slots.GetValueOrDefault(m.Groups[1].Value, m.Value));
                TestContext.Out.WriteLine($"BOT [{opener.Invites}] {text}");
                string[] chain = VC.AnswerChain(opener.Invites);
                if (AutonomousChatShortTalk.QuestionShape(text) == "ask_choice" && VC.InviteFamily(opener.Invites) == "ask" && !chain.Contains("ask_choice"))
                    chain = ["ask_choice", .. chain];
                Intent read = AutonomousChatIntentModel.Predict(text);
                string alarmIntent = read == Intent.Alarm ? "alarm" : read == Intent.RvR && VC.InviteFamily(opener.Invites) is "chat" or "news" ? "rvr" : null;
                bool alarm = alarmIntent != null;
                if (alarm)
                    chain = [$"({alarmIntent})"];
                foreach (string answers in chain)
                {
                    VC.Picked picked;
                    bool found = alarm
                        ? Pick(corpus, speaker with { Id = random.Next(1000) }, random, out picked, alarmIntent,
                            filter: line => AutonomousChatShortTalk.ReplyFits(text, line.Text))
                        : Pick(corpus, speaker with { Id = random.Next(1000) }, random, out picked, answers: answers,
                            filter: line => AutonomousBotVoices.ShapedFits(answers, text, line.Text));
                    if (!found)
                        continue;
                    total++;
                    bool asks = picked.Text.TrimEnd().EndsWith('?');
                    if (asks) dangling++;
                    TestContext.Out.WriteLine($"    -> ({answers}) {picked.Text}{(asks ? "   <-- question nobody answers" : "")}");
                    break;
                }
            }
            TestContext.Out.WriteLine($"replies that ask a question nobody answers: {dangling} of {total}");
        }
    }
}
