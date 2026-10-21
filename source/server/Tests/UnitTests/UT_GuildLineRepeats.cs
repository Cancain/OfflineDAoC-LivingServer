using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>Live run 2026-10-21: "died. the run back is the worst part" three times in /gu in 17 minutes.</summary>
    [TestFixture]
    public class UT_GuildLineRepeats
    {
        [Test]
        public void AGuildDoesNotHearTheSameLineWithinTheHour() => Assert.Multiple(() =>
        {
            const string guild = "ut-guild-repeats";
            AutonomousBotGuildSocial.NoteHeard(guild, "died. the run back is the worst part", 1_000);
            int call = 0;
            string Next() => call++ % 2 == 0 ? "died. the run back is the worst part" : "ugh, died in Camelot Hills";
            Assert.That(AutonomousBotGuildSocial.FreshLine(guild, Next, 60_000), Is.EqualTo("ugh, died in Camelot Hills"));
            Assert.That(AutonomousBotGuildSocial.FreshLine(guild, () => "died. the run back is the worst part", 60_000), Is.Null,
                "nothing new to say: say nothing");
            Assert.That(AutonomousBotGuildSocial.FreshLine(guild, () => "died. the run back is the worst part",
                1_000 + AutonomousBotGuildSocial.RecentGuildLineMs), Is.Not.Null, "an hour later it may come back");
            Assert.That(AutonomousBotGuildSocial.FreshLine("ut-other-guild", () => "died. the run back is the worst part", 60_000), Is.Not.Null,
                "another guild never heard it");
        });
    }
}
