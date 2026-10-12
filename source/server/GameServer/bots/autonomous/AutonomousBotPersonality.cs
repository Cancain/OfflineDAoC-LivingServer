using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using DOL.GS.ServerProperties;

namespace DOL.GS;

/// <summary>A bot's personality type (docs/BOT-PERSONALITIES.md).</summary>
public enum BotPersonalityType
{
    Leveler,
    Socialite,
    Daredevil,
    Explorer,
    Crafter,
    NoLifer,
}

/// <summary>Small persistent traits, 0-9, fixed from the bot's database id.</summary>
public readonly record struct BotPersonalityTraits(int Curiosity, int Risk, int Sociability, int Patience, int Chattiness);

public readonly record struct BotPersonality(BotPersonalityType Type, BotPersonalityTraits Traits);

/// <summary>
/// Bot personalities (docs/BOT-PERSONALITIES.md, part of the Social Expansion). Every autonomous
/// gamebot has a type and traits, fixed from its database id, that tilt how it spends its time:
/// town breaks, solo versus group goals, dungeon versus outdoor, which legal camp it picks, and how
/// often it talks. Hard rules never change: realm, reachability, level and con legality, recovery,
/// services and the owner's gameplay rules. With <c>bot_personalities_enabled</c> off every tilt is
/// neutral and behavior is exactly as before.
/// </summary>
public static class AutonomousBotPersonality
{
    /// <summary>Type shares in percent, in enum order (sum 100).</summary>
    public static readonly int[] TypeSharePercent = [28, 20, 20, 16, 12, 4];

    public const int ZoneMemoryCapacity = 32;
    public static readonly TimeSpan ZoneFreshAfter = TimeSpan.FromHours(6);

    public static bool Enabled => Properties.BOT_PERSONALITIES_ENABLED;

    #region Assignment

    /// <summary>A well-mixed 64-bit value from an id and a salt (SplitMix64).</summary>
    public static ulong Mix(long id, ulong salt)
    {
        unchecked
        {
            ulong z = (ulong)id + salt * 0x9E3779B97F4A7C15UL + 0x9E3779B97F4A7C15UL;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }
    }

    public static BotPersonalityType TypeFor(long botId)
    {
        int roll = (int)(Mix(botId, 1) % 100);
        for (int index = 0; index < TypeSharePercent.Length; index++)
        {
            if (roll < TypeSharePercent[index])
                return (BotPersonalityType)index;
            roll -= TypeSharePercent[index];
        }
        return BotPersonalityType.Leveler;
    }

    /// <summary>Trait ranges by type: each trait is drawn within its type's band, so types differ but individuals vary.</summary>
    private static (int Low, int High) Band(BotPersonalityType type, int trait) => (type, trait) switch
    {
        // trait: 0 curiosity, 1 risk, 2 sociability, 3 patience, 4 chattiness
        (BotPersonalityType.Leveler, 0) => (1, 4), (BotPersonalityType.Leveler, 1) => (3, 6), (BotPersonalityType.Leveler, 2) => (2, 5),
        (BotPersonalityType.Leveler, 3) => (5, 9), (BotPersonalityType.Leveler, 4) => (1, 5),
        (BotPersonalityType.Socialite, 0) => (3, 6), (BotPersonalityType.Socialite, 1) => (2, 5), (BotPersonalityType.Socialite, 2) => (7, 9),
        (BotPersonalityType.Socialite, 3) => (3, 7), (BotPersonalityType.Socialite, 4) => (6, 9),
        (BotPersonalityType.Daredevil, 0) => (3, 7), (BotPersonalityType.Daredevil, 1) => (7, 9), (BotPersonalityType.Daredevil, 2) => (3, 6),
        (BotPersonalityType.Daredevil, 3) => (1, 4), (BotPersonalityType.Daredevil, 4) => (4, 8),
        (BotPersonalityType.Explorer, 0) => (7, 9), (BotPersonalityType.Explorer, 1) => (4, 7), (BotPersonalityType.Explorer, 2) => (2, 6),
        (BotPersonalityType.Explorer, 3) => (3, 7), (BotPersonalityType.Explorer, 4) => (3, 7),
        (BotPersonalityType.Crafter, 0) => (2, 5), (BotPersonalityType.Crafter, 1) => (0, 3), (BotPersonalityType.Crafter, 2) => (4, 7),
        (BotPersonalityType.Crafter, 3) => (6, 9), (BotPersonalityType.Crafter, 4) => (3, 7),
        (BotPersonalityType.NoLifer, 0) => (2, 6), (BotPersonalityType.NoLifer, 1) => (6, 9), (BotPersonalityType.NoLifer, 2) => (3, 7),
        (BotPersonalityType.NoLifer, 3) => (6, 9), (BotPersonalityType.NoLifer, 4) => (5, 9),
        _ => (3, 6),
    };

    public static BotPersonality For(long botId)
    {
        BotPersonalityType type = TypeFor(botId);
        int Trait(int index)
        {
            (int low, int high) = Band(type, index);
            return low + (int)(Mix(botId, 10UL + (ulong)index) % (ulong)(high - low + 1));
        }
        return new BotPersonality(type, new BotPersonalityTraits(Trait(0), Trait(1), Trait(2), Trait(3), Trait(4)));
    }

    public static BotPersonality For(GameBot bot) => For(bot?.DatabaseID ?? 0);

    public static bool Applies(GameBot bot) =>
        Enabled && bot?.IsAutonomousWorldBot == true && !bot.IsTemporaryGroupHelper && bot.DatabaseID > 0;

    #endregion

    #region Tilts (pure; neutral values when off)

    /// <summary>Chance of a town break at a task boundary (today: 15% for everyone).</summary>
    public static double TownBreakChance(BotPersonality personality) => personality.Type switch
    {
        BotPersonalityType.Socialite => 0.30,
        BotPersonalityType.Crafter => 0.28,
        BotPersonalityType.Explorer => 0.10,
        BotPersonalityType.Daredevil => 0.10,
        BotPersonalityType.Leveler => 0.07,
        BotPersonalityType.NoLifer => 0.05,
        _ => AutonomousTownDowntime.StartChancePerEligibilityCheck,
    } * (0.8 + personality.Traits.Sociability * 0.05);

    /// <summary>Town break length as a share of the normal 15-30 minutes (1.0 = today).</summary>
    public static double TownBreakLengthFactor(BotPersonality personality) => personality.Type switch
    {
        BotPersonalityType.Socialite => 1.5,
        BotPersonalityType.Crafter => 1.4,
        BotPersonalityType.Leveler or BotPersonalityType.NoLifer => 0.7,
        _ => 1.0,
    };

    /// <summary>
    /// Goal tilt: the chance to re-draw a goal the type dislikes from the owner's configured mix.
    /// Social types re-draw some solo goals hoping for a group; solitary types re-draw some group
    /// goals. A re-draw comes from the same configured mix, so no goal type is ever forced or banned.
    /// </summary>
    public static double RedrawChance(BotPersonality personality, eAutonomousObjectiveKind first) => (personality.Type, first) switch
    {
        (BotPersonalityType.Socialite, eAutonomousObjectiveKind.SoloPve) => 0.45,
        (BotPersonalityType.NoLifer, eAutonomousObjectiveKind.SoloPve) => 0.55,
        (BotPersonalityType.Leveler, eAutonomousObjectiveKind.GroupPve) => 0.25,
        (BotPersonalityType.Explorer, eAutonomousObjectiveKind.GroupPve) => 0.35,
        (BotPersonalityType.Crafter, eAutonomousObjectiveKind.RvR) => 0.5,
        (BotPersonalityType.Daredevil, eAutonomousObjectiveKind.SoloPve) => 0.2,
        _ => 0,
    };

    /// <summary>Dungeon preference as a percentage of today's (100 = unchanged).</summary>
    public static int DungeonPreferencePercent(BotPersonality personality) => personality.Type switch
    {
        BotPersonalityType.Daredevil => 170,
        BotPersonalityType.NoLifer => 150,
        BotPersonalityType.Explorer => 130,
        BotPersonalityType.Socialite => 100,
        BotPersonalityType.Leveler => 80,
        BotPersonalityType.Crafter => 60,
        _ => 100,
    };

    /// <summary>
    /// Extra weight (percent) for one legal outdoor camp, on top of the live-spawn weight:
    /// Daredevils like the harder cons of their legal range, Explorers like zones they haven't seen
    /// lately, Levelers like full camps. Never zero: every legal camp stays possible.
    /// </summary>
    public static int CampWeightPercent(BotPersonality personality, ConColor typicalCon, bool zoneIsFresh, int liveMobCount)
    {
        int weight = 100;
        int risk = personality.Traits.Risk;
        if (typicalCon >= ConColor.YELLOW)
            weight = weight * (personality.Type == BotPersonalityType.Daredevil ? 200 + risk * 15 : 60 + risk * 8) / 100;
        else if (typicalCon <= ConColor.GREEN)
            weight = weight * (personality.Type == BotPersonalityType.Daredevil ? 50 : 100 + (9 - risk) * 5) / 100;
        if (zoneIsFresh)
            weight = weight * (personality.Type == BotPersonalityType.Explorer ? 250 + personality.Traits.Curiosity * 25 : 100 + personality.Traits.Curiosity * 5) / 100;
        if (personality.Type == BotPersonalityType.Leveler && liveMobCount >= 4)
            weight = weight * 140 / 100;
        return Math.Max(10, weight);
    }

    /// <summary>Talk-rate multiplier for ambient chat (1.0 = today).</summary>
    public static double ChatRateFactor(BotPersonality personality) => 0.25 + personality.Traits.Chattiness * 0.145;

    #endregion

    #region Live hooks (each returns today's behavior when personalities are off)

    public static bool RollTownBreak(GameBot bot, double roll) =>
        Applies(bot) ? roll >= 0 && roll < TownBreakChance(For(bot)) : AutonomousTownDowntime.RollAtTaskBoundary(roll);

    public static TimeSpan? ScaleTownBreak(GameBot bot, TimeSpan? duration, TimeSpan remaining)
    {
        if (duration == null || !Applies(bot))
            return duration;
        TimeSpan scaled = TimeSpan.FromTicks((long)(duration.Value.Ticks * TownBreakLengthFactor(For(bot))));
        if (scaled > remaining)
            scaled = remaining;
        return scaled < TimeSpan.FromMinutes(5) ? TimeSpan.FromMinutes(5) : scaled;
    }

    /// <summary>A goal from the owner's configured mix, tilted by personality.</summary>
    public static eAutonomousObjectiveKind ChooseGoal(GameBot bot, Func<eAutonomousObjectiveKind> draw, Random random = null)
    {
        eAutonomousObjectiveKind first = draw();
        if (!Applies(bot))
            return first;
        random ??= Random.Shared;
        return random.NextDouble() < RedrawChance(For(bot), first) ? draw() : first;
    }

    public static int DungeonPreferencePercent(GameBot bot) => Applies(bot) ? DungeonPreferencePercent(For(bot)) : 100;

    public static Func<AutonomousBotDecisionEngine.Camp, int> CampWeigher(GameBot bot)
    {
        if (!Applies(bot))
            return null;
        BotPersonality personality = For(bot);
        long botId = bot.DatabaseID;
        DateTime now = DateTime.UtcNow;
        return camp => CampWeightPercent(personality, camp.TypicalCon, IsZoneFresh(botId, camp.ZoneName, now), camp.LiveMobCount);
    }

    public static double ChatRateFactor(GameBot bot) => Applies(bot) ? ChatRateFactor(For(bot)) : 1.0;

    #endregion

    #region Zone memory (in memory; "lately" means since the server started, at most 32 zones)

    private static readonly ConcurrentDictionary<long, ZoneMemory> Memories = new();

    private sealed class ZoneMemory
    {
        private readonly Dictionary<string, DateTime> _visits = new(StringComparer.OrdinalIgnoreCase);

        public void Visit(string zone, DateTime now)
        {
            lock (_visits)
            {
                _visits[zone] = now;
                if (_visits.Count > ZoneMemoryCapacity)
                    _visits.Remove(_visits.OrderBy(pair => pair.Value).First().Key);
            }
        }

        public bool IsFresh(string zone, DateTime now)
        {
            lock (_visits)
                return !_visits.TryGetValue(zone, out DateTime last) || now - last >= ZoneFreshAfter;
        }
    }

    public static void RememberZone(GameBot bot, string zone)
    {
        if (!Applies(bot) || string.IsNullOrWhiteSpace(zone))
            return;
        Memories.GetOrAdd(bot.DatabaseID, _ => new ZoneMemory()).Visit(zone, DateTime.UtcNow);
    }

    public static bool IsZoneFresh(long botId, string zone, DateTime now) =>
        string.IsNullOrWhiteSpace(zone) || !Memories.TryGetValue(botId, out ZoneMemory memory) || memory.IsFresh(zone, now);

    /// <summary>Tests only: a memory with fixed times.</summary>
    public static void RememberZoneAt(long botId, string zone, DateTime when) =>
        Memories.GetOrAdd(botId, _ => new ZoneMemory()).Visit(zone, when);

    #endregion

    public static string Describe(BotPersonality personality) =>
        $"{personality.Type} (curiosity {personality.Traits.Curiosity}, risk {personality.Traits.Risk}, " +
        $"sociability {personality.Traits.Sociability}, patience {personality.Traits.Patience}, chattiness {personality.Traits.Chattiness})";
}
