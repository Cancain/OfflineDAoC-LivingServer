using System;
using System.Linq;
using System.Text.RegularExpressions;

namespace DOL.GS;

/// <summary>
/// Answers from the live world for questions the reply corpus can only guess at (chat audit 2026-10-21): where people of a
/// level are hunting right now, where the enemy has been seen, whether a bot is in the place a player asked about, and where
/// the bot is. Every answer names what is really true on this server at that moment, or nothing.
/// </summary>
public static class AutonomousChatLiveAnswers
{
    /// <summary>The level asked about ("good camp for 24?"), else the asker's, else the bot's.</summary>
    public static int LevelAsked(string text, int fallback)
    {
        foreach (Match match in Regex.Matches(text ?? string.Empty, @"\b(\d{1,2})s?\b"))
            if (int.TryParse(match.Groups[1].Value, out int level) && level is >= 1 and <= 50)
                return level;
        return fallback;
    }

    /// <summary>"where is a good place to level at 24?": the zone where bots of that level are camping now, and a dungeon for it.</summary>
    public static string WhereToHunt(GameBot bot, GamePlayer asker, string incoming, Random random)
    {
        if (bot == null)
            return null;
        int level = LevelAsked(incoming, asker?.Level ?? bot.Level);
        string zone = AutonomousBotRegistry.Snapshot()
            .Where(other => other.Realm == bot.Realm && other.IsAlive && Math.Abs(other.Level - level) <= 2 &&
                            !string.IsNullOrEmpty(other.PersistentRecord?.CurrentCampId) && other.CurrentZone != null &&
                            !other.CurrentZone.IsRvR && other.CurrentRegion?.IsRvR != true &&
                            !AutonomousBotVoices.IsCapitalRegion(other.CurrentRegionID) && !string.IsNullOrWhiteSpace(other.CurrentZone.Description))
            .GroupBy(other => other.CurrentZone.Description)
            .OrderByDescending(group => group.Count())
            .Select(group => group.Key)
            .FirstOrDefault();
        string dungeon = level >= 7 ? AutonomousBotVoices.DungeonFor(bot.Realm, level) : null;
        if (zone != null && dungeon != null && !zone.Contains(dungeon, StringComparison.OrdinalIgnoreCase))
            return random.Next(3) switch
            {
                0 => $"for {level} try {zone}, lots of people camping there right now. or {dungeon} if you get a group",
                1 => $"{zone} is busy with {level}s at the moment, {dungeon} is good too with a group",
                _ => $"{dungeon} with a group, or {zone} solo, thats where the {level}s are",
            };
        if (zone != null)
            return random.Next(2) == 0 ? $"{zone}, saw a bunch of {level}s camping there" : $"try {zone}, thats where the {level}s are right now";
        if (dungeon != null)
            return random.Next(2) == 0 ? $"{dungeon} is good around {level} if you can get a group" : $"{dungeon} for {level}, bring a group";
        return null;
    }

    /// <summary>"where are the mids?": the frontier zone with the most enemy gamebots in it now, or that it is quiet.</summary>
    public static string EnemySighting(GameBot bot, Random random)
    {
        if (bot == null)
            return null;
        var seen = AutonomousBotRegistry.Snapshot()
            .Where(other => other.Realm != bot.Realm && other.Realm is eRealm.Albion or eRealm.Midgard or eRealm.Hibernia && other.IsAlive &&
                            other.CurrentZone != null && (other.CurrentZone.IsRvR || other.CurrentRegion?.IsRvR == true) &&
                            !string.IsNullOrWhiteSpace(other.CurrentZone.Description))
            .GroupBy(other => (other.Realm, Zone: other.CurrentZone.Description))
            .OrderByDescending(group => group.Count())
            .FirstOrDefault();
        if (seen == null)
            return random.Next(2) == 0 ? "havent seen any, quiet out there right now" : "quiet atm, no enemies that i know of";
        string enemy = seen.Key.Realm switch { eRealm.Albion => "albs", eRealm.Midgard => "mids", _ => "hibs" };
        return seen.Count() >= 8
            ? random.Next(2) == 0 ? $"big group of {enemy} in {seen.Key.Zone}" : $"{enemy} zerg in {seen.Key.Zone} last i heard"
            : random.Next(2) == 0 ? $"saw some {enemy} around {seen.Key.Zone}" : $"a few {enemy} in {seen.Key.Zone}";
    }

    /// <summary>True when the bot is in the place a player named ("camelot", "black mountains", "the frontier").</summary>
    public static bool IsIn(GameBot bot, string place)
    {
        if (bot == null || string.IsNullOrWhiteSpace(place))
            return false;
        if (place is "frontier" or "rvr" or "the frontier")
            return bot.CurrentZone?.IsRvR == true || bot.CurrentRegion?.IsRvR == true;
        string[] texts = [bot.CurrentZone?.Description, bot.CurrentRegion?.Description, bot.PersistentRecord?.TravelDestination];
        return texts.Any(text => !string.IsNullOrWhiteSpace(text) && text.Contains(place, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>"anyone in camelot?" answered by a bot that is there; null from one that isn't.</summary>
    public static string InPlace(GameBot bot, string place, Random random)
    {
        if (!IsIn(bot, place))
            return null;
        string zone = bot.CurrentZone?.Description ?? place;
        return random.Next(3) switch
        {
            0 => $"here, in {zone}",
            1 => $"im in {zone}, whats up?",
            _ => $"yep, {zone}",
        };
    }

    /// <summary>"where are you?": the bot's zone, level and class.</summary>
    public static string WhereIAm(GameBot bot, GamePlayer asker, Random random) =>
        bot == null ? null : AutonomousBotChatCoordinator.WhereText(string.IsNullOrWhiteSpace(bot.CurrentZone?.Description) ? "the frontier" : bot.CurrentZone.Description.Trim(),
            bot.CurrentZone != null && asker != null && bot.CurrentZone == asker.CurrentZone, bot.Level, bot.CharacterClass?.Name ?? "adventurer", random);
}
