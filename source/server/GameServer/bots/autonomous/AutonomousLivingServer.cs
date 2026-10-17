using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using DOL.Database;
using DOL.Events;
using DOL.GS.Keeps;
using DOL.GS.PacketHandler;
using DOL.GS.ServerProperties;
using DOL.Logging;

namespace DOL.GS;

/// <summary>
/// The Living Server (docs/LIVING-SERVER.md): autonomous gamebots remember you, congratulate dings,
/// celebrate server firsts, ask for and give rezzes, raise frontier alarms and keep nemeses. Every
/// part has its own server setting (category "bots"), all off by default, and only autonomous
/// gamebots speak; companion bots and real players are never changed. Lines come from the voices
/// corpus (living_server.lines and memory.lines) and are only said where a real player can hear.
/// </summary>
public static partial class AutonomousLivingServer
{
    private static readonly Logger Log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);

    public static bool MemoryOn => Properties.BOT_LIVING_MEMORY;
    public static bool GratsOn => Properties.BOT_LIVING_GRATS;
    public static bool FirstsOn => Properties.BOT_LIVING_FIRSTS;
    public static bool DeathOn => Properties.BOT_LIVING_DEATH;
    public static bool AlarmsOn => Properties.BOT_LIVING_ALARMS;
    public static bool NemesisOn => Properties.BOT_LIVING_NEMESIS;

    public static bool AnyOn => MemoryOn || GratsOn || FirstsOn || DeathOn || AlarmsOn || NemesisOn ||
                                AutonomousBotSchedule.Active;

    public const int FlushIntervalMs = 5_000;

    internal static readonly LivingServerTable<(long BotId, string Player), OfflineBotMemoryRecord> Memories =
        new("memory", row => (row.BotId, row.PlayerName), new BotNameComparer());
    internal static readonly LivingServerTable<(long BotId, string Killer), OfflineBotNemesisRecord> Nemeses =
        new("nemesis", row => (row.BotId, row.KillerName), new BotNameComparer());
    internal static readonly LivingServerTable<string, OfflineServerFirstRecord> Firsts =
        new("server first", row => row.Title, StringComparer.OrdinalIgnoreCase);

    private static Timer _flushTimer;
    private static long _nextPulse;

    private sealed class BotNameComparer : IEqualityComparer<(long, string)>
    {
        public bool Equals((long, string) a, (long, string) b) =>
            a.Item1 == b.Item1 && string.Equals(a.Item2, b.Item2, StringComparison.OrdinalIgnoreCase);

        public int GetHashCode((long, string) key) =>
            HashCode.Combine(key.Item1, StringComparer.OrdinalIgnoreCase.GetHashCode(key.Item2 ?? string.Empty));
    }

    #region Server lifecycle

    [GameServerStartedEvent]
    public static void OnServerStarted(DOLEvent e, object sender, EventArgs args)
    {
        Load("memory", () => Memories.Load(GameServer.Database.SelectAllObjects<OfflineBotMemoryRecord>()));
        Load("nemesis", () => Nemeses.Load(GameServer.Database.SelectAllObjects<OfflineBotNemesisRecord>()));
        Load("server firsts", () => Firsts.Load(GameServer.Database.SelectAllObjects<OfflineServerFirstRecord>()));
        if (FirstsOn)
            Load("server firsts reached before records began", SeedFirsts);
        GameEventMgr.AddHandler(GamePlayerEvent.LevelUp, new DOLEventHandler(OnPlayerLevelUp));
        GameEventMgr.AddHandler(GamePlayerEvent.RRLevelUp, new DOLEventHandler(OnPlayerRealmRankUp));
        _flushTimer = new Timer(_ => FlushAll(), null, FlushIntervalMs, FlushIntervalMs);
        if (Log.IsInfoEnabled)
            Log.Info($"Living Server: {Memories.Count} memories, {Nemeses.Count} nemesis rows, {Firsts.Count} server firsts " +
                     $"(memory {MemoryOn}, grats {GratsOn}, firsts {FirstsOn}, death {DeathOn}, alarms {AlarmsOn}, " +
                     $"nemesis {NemesisOn}, schedule {Properties.BOT_SCHEDULE_MODE}, breaks {Properties.BOT_LIVING_BREAKS}).");
    }

    [GameServerStoppedEvent]
    public static void OnServerStopped(DOLEvent e, object sender, EventArgs args)
    {
        GameEventMgr.RemoveHandler(GamePlayerEvent.LevelUp, new DOLEventHandler(OnPlayerLevelUp));
        GameEventMgr.RemoveHandler(GamePlayerEvent.RRLevelUp, new DOLEventHandler(OnPlayerRealmRankUp));
        _flushTimer?.Dispose();
        _flushTimer = null;
        FlushAll();
    }

    public static void FlushAll()
    {
        Memories.Flush();
        Nemeses.Flush();
        Firsts.Flush();
    }

    private static void Load(string what, Action load)
    {
        try
        {
            load();
        }
        catch (Exception exception)
        {
            Log.Error($"Living Server: could not load {what}", exception);
        }
    }

    /// <summary>Game-loop pulse (from the group coordinator's tick). Cheap when everything is off.</summary>
    public static void Pulse(long now)
    {
        if (now < _nextPulse)
            return;
        _nextPulse = now + 1_000;
        try
        {
            AutonomousBotSchedule.Pulse(now);
            if (MemoryOn)
                MemoryPulse(now);
        }
        catch (Exception exception)
        {
            Log.Error("Living Server: pulse failed", exception);
        }
    }

    #endregion

    #region Speaking

    internal static bool IsSpeaker(GameBot bot) => bot?.IsAutonomousWorldBot == true && !bot.IsTemporaryGroupHelper &&
        bot.ObjectState == GameObject.eObjectState.Active && bot.DatabaseID > 0;

    internal static bool CanTalk(GameBot bot) => IsSpeaker(bot) && bot.IsAlive && !bot.InCombat && !bot.IsCasting;

    internal static bool PlayerHears(GameBot bot) => bot?.CurrentRegion != null &&
        ClientService.Instance.GetPlayersOfRegion(bot.CurrentRegion).Any(player =>
            player.ObjectState == GameObject.eObjectState.Active && bot.IsWithinRadius(player, WorldMgr.SAY_DISTANCE));

    internal static bool GroupHasPlayer(Group group) =>
        group != null && group.GetMembersInTheGroup().Any(member => member is GamePlayer);

    internal static bool RealmHasPlayer(eRealm realm) => ClientService.Instance.GetPlayersOfRealm(realm).Count > 0;

    internal enum Channel { Say, Group, Faction, Guild }

    internal static void Speak(GameBot bot, Channel channel, string text)
    {
        if (string.IsNullOrWhiteSpace(text) || !IsSpeaker(bot))
            return;
        switch (channel)
        {
            case Channel.Say:
                if (PlayerHears(bot))
                    bot.Say(text);
                break;
            case Channel.Group:
                if (GroupHasPlayer(bot.Group))
                    bot.Group.SendMessageToGroupMembers(bot, text, eChatType.CT_Group, eChatLoc.CL_ChatWindow);
                break;
            case Channel.Faction:
                if (RealmHasPlayer(bot.Realm))
                    AutonomousBotChatCoordinator.BroadcastFaction(bot.Name, bot.Realm, text);
                break;
            case Channel.Guild:
                if (bot.Guild != null && AutonomousBotGuildSocial.HasListener(bot.Guild))
                    AutonomousBotGuildSocial.SendGuildLine(bot.Guild, bot.Name, text);
                break;
        }
    }

    /// <summary>Runs an action on the bot's timer after a delay, if the condition still holds then.</summary>
    internal static void Later(GameBot bot, int delayMs, Func<bool> stillValid, Action action)
    {
        if (bot == null)
            return;
        _ = new ECSGameTimer(bot, _ =>
        {
            try
            {
                if (bot.ObjectState == GameObject.eObjectState.Active && (stillValid == null || stillValid()))
                    action();
            }
            catch (Exception exception)
            {
                Log.Warn($"Living Server: delayed line for {bot.Name} failed", exception);
            }
            return 0;
        }, Math.Max(1, delayMs));
    }

    internal static string ClassOf(GameLiving living) => living switch
    {
        GamePlayer player => player.CharacterClass?.Name ?? string.Empty,
        GameBot bot => bot.CharacterClass?.Name ?? bot.ClassName ?? string.Empty,
        _ => string.Empty,
    };

    /// <summary>A race as players say it ("troll", "half ogre", "minotaur").</summary>
    public static string RaceWord(int race)
    {
        if (race is >= 19 and <= 21)
            return "minotaur";
        eRace value = (eRace)race;
        if (value == eRace.Unknown || !Enum.IsDefined(value))
            return string.Empty;
        return value == eRace.HalfOgre ? "half ogre" : value.ToString().ToLowerInvariant();
    }

    internal static string RaceOf(GameLiving living) => living switch
    {
        GamePlayer player => RaceWord(player.Race),
        GameBot bot => RaceWord(bot.RaceId),
        _ => string.Empty,
    };

    /// <summary>How players named the other realms in chat.</summary>
    public static string RealmPlural(eRealm realm) => realm switch
    {
        eRealm.Albion => "albs",
        eRealm.Midgard => "mids",
        eRealm.Hibernia => "hibs",
        _ => string.Empty,
    };

    internal static string PlaceOf(GameLiving living) => living?.CurrentZone?.Description ?? string.Empty;

    /// <summary>The frontier keep nearest to a point in the same region (within 6,000 units), or the zone's name.</summary>
    internal static string FrontierPlaceOf(GameLiving living)
    {
        try
        {
            AbstractGameKeep nearest = GameServer.KeepManager.GetFrontierKeeps()
                .Where(keep => keep.Region == living.CurrentRegionID && !keep.IsPortalKeep && !string.IsNullOrEmpty(keep.Name))
                .OrderBy(keep => living.GetDistanceTo(new Point3D(keep.X, keep.Y, keep.Z)))
                .FirstOrDefault();
            if (nearest != null && living.GetDistanceTo(new Point3D(nearest.X, nearest.Y, nearest.Z)) <= 6_000)
                return nearest.Name;
        }
        catch
        {
            // fall back to the zone
        }
        return PlaceOf(living);
    }

    /// <summary>A real player of a class that can resurrect in 2002-2003.</summary>
    public static bool IsRezClass(GamePlayer player) => player?.CharacterClass?.ID is
        (int)eCharacterClass.Cleric or (int)eCharacterClass.Friar or (int)eCharacterClass.Healer or
        (int)eCharacterClass.Shaman or (int)eCharacterClass.Druid or (int)eCharacterClass.Warden or
        (int)eCharacterClass.Bard;

    #endregion
}
