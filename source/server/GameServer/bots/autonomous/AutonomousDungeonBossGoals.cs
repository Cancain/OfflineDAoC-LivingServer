using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DOL.Database;

namespace DOL.GS;

/// <summary>
/// Dungeon bosses as a party goal (owner, 2026-10-20). Dungeons are not made more attractive: a party that is already
/// grinding a camp in a dungeon also goes for that dungeon's named boss, once per task, when the boss is the kill target
/// of a real quest at the party's level (the DataQuest table) or has its own drop table, and the fight suits the party's
/// size. The party then returns to its camp. Bots do not run the quests themselves; the quest only says which bosses
/// matter at which level.
///
/// Before this, none of the 178 named monsters in the classic and Shrouded Isles dungeons was ever a goal: the camp
/// catalog drops capitalized names, so bots met bosses like Favonius Facilis (Tomb of Mithra) only by stumbling into them.
/// </summary>
public static class AutonomousDungeonBossGoals
{
    public readonly record struct Boss(string Name, ushort RegionId, string Quest, int QuestMinLevel);

    /// <summary>Minutes a party grinds its dungeon camp before it goes for the boss.</summary>
    public const long GrindBeforeBossMilliseconds = 10 * 60_000;
    /// <summary>Longest a party spends on one boss before returning to its camp.</summary>
    public const long BossAttemptMilliseconds = 15 * 60_000;
    public const long BossCheckMilliseconds = 2 * 60_000;

    private static readonly object Sync = new();
    private static Dictionary<(ushort Region, string Name), Boss> _questBosses;
    private static int _loading;
    private static readonly ConcurrentDictionary<string, bool> OwnDrops = new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<string, byte> DropLookups = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Pure rule: whether a party goes for a boss. A quest boss needs the party at the quest's level; any boss needs
    /// a reason (a quest or its own drops) and a fight the party can take: blue to yellow for 3-5 bots, up to orange
    /// for six or more, never grey.
    /// </summary>
    public static bool Qualifies(int partyLevel, int partySize, int bossLevel, int questMinLevel, bool hasOwnDrops)
    {
        bool quest = questMinLevel > 0;
        if (!quest && !hasOwnDrops) return false;
        if (quest && partyLevel < questMinLevel) return false;
        if (partySize < 3) return false;
        ConColor con = ConLevels.GetConColor(ConLevels.GetConLevel(Math.Clamp(partyLevel, 0, 127), Math.Clamp(bossLevel, 0, 127)));
        ConColor most = partySize >= 6 ? ConColor.ORANGE : ConColor.YELLOW;
        return con > ConColor.GREY && con <= most;
    }

    /// <summary>Pure parser: the "Name;region|Name;region" kill targets of one DataQuest row.</summary>
    public static IEnumerable<(string Name, ushort Region)> QuestTargets(string targetName)
    {
        foreach (string part in (targetName ?? string.Empty).Split('|'))
        {
            string[] fields = part.Split(';');
            if (fields.Length < 2 || string.IsNullOrWhiteSpace(fields[0]) || !ushort.TryParse(fields[1].Trim(), out ushort region)) continue;
            string name = fields[0].Trim();
            if (name.Length > 0 && char.IsUpper(name[0])) yield return (name, region);
        }
    }

    public static string Reason(Boss boss, bool ownDrops) =>
        boss.QuestMinLevel > 0 ? $"for the {boss.Quest} quest" : ownDrops ? "for its rare drop" : "for its drop";

    /// <summary>The quest boss with this name in this region, if any (loads the quest table in the background).</summary>
    public static bool TryGetQuestBoss(ushort region, string name, out Boss boss)
    {
        boss = default;
        var bosses = Volatile.Read(ref _questBosses);
        if (bosses == null) { BeginLoad(); return false; }
        return bosses.TryGetValue((region, name ?? string.Empty), out boss);
    }

    /// <summary>Whether a named monster has its own drop table; false until the background lookup has answered.</summary>
    public static bool HasOwnDrops(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        if (OwnDrops.TryGetValue(name, out bool drops)) return drops;
        if (DropLookups.TryAdd(name, 0))
            Task.Run(() =>
            {
                try
                {
                    var links = DOLDB<DbMobXLootTemplate>.SelectObjects(DB.Column("MobName").IsEqualTo(name.ToLowerInvariant()))
                        .Concat(DOLDB<DbMobXLootTemplate>.SelectObjects(DB.Column("MobName").IsEqualTo(name))).ToArray();
                    bool any = links.Any(link => DOLDB<DbLootTemplate>.SelectObjects(DB.Column("TemplateName").IsEqualTo(link.LootTemplateName))
                        .Any(row => !string.IsNullOrWhiteSpace(row.ItemTemplateID)));
                    OwnDrops[name] = any;
                }
                catch { OwnDrops[name] = false; }
            });
        return false;
    }

    private static void BeginLoad()
    {
        if (Interlocked.Exchange(ref _loading, 1) == 1) return;
        Task.Run(() =>
        {
            var map = new Dictionary<(ushort, string), Boss>();
            try
            {
                foreach (DbDataQuest quest in GameServer.Database.SelectAllObjects<DbDataQuest>())
                    foreach (var (name, region) in QuestTargets(quest.TargetName))
                    {
                        var key = (region, name);
                        if (!map.TryGetValue(key, out Boss known) || quest.MinLevel < known.QuestMinLevel)
                            map[key] = new Boss(name, region, quest.Name, Math.Max(1, (int)quest.MinLevel));
                    }
            }
            catch { }
            Volatile.Write(ref _questBosses, map.Count == 0 ? new Dictionary<(ushort, string), Boss>() : WithComparer(map));
        });
    }

    private static Dictionary<(ushort Region, string Name), Boss> WithComparer(Dictionary<(ushort, string), Boss> map) =>
        new(map.Select(pair => new KeyValuePair<(ushort, string), Boss>((pair.Key.Item1, pair.Key.Item2), pair.Value)), new KeyComparer());

    private sealed class KeyComparer : IEqualityComparer<(ushort Region, string Name)>
    {
        public bool Equals((ushort Region, string Name) a, (ushort Region, string Name) b) =>
            a.Region == b.Region && string.Equals(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
        public int GetHashCode((ushort Region, string Name) key) => HashCode.Combine(key.Region, StringComparer.OrdinalIgnoreCase.GetHashCode(key.Name ?? ""));
    }

    /// <summary>Tests only.</summary>
    public static void SetForTests(IEnumerable<Boss> bosses, IEnumerable<string> withDrops = null)
    {
        Volatile.Write(ref _questBosses, WithComparer(bosses.ToDictionary(boss => (boss.RegionId, boss.Name), boss => boss)));
        Interlocked.Exchange(ref _loading, 1);
        OwnDrops.Clear();
        foreach (string name in withDrops ?? []) OwnDrops[name] = true;
    }
}
