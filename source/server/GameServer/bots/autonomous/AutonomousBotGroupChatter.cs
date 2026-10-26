using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using DOL.GS.PacketHandler;
using VC = DOL.GS.AutonomousBotVoiceCorpus;

namespace DOL.GS;

/// <summary>
/// Talk inside the real player's group (bot voices, 0.36-se.4). Gamebots in a player's group never said
/// anything unprompted (BotBrain skipped them), so a group of bots felt like a group of pets. Now, out of
/// combat, one of them says a corpus "group" line in /group every 4-8 minutes (the first one or two minutes
/// after the group forms), and a groupmate may answer it. Never during a fight, and only with bot voices on.
/// </summary>
public static class AutonomousBotGroupChatter
{
    public const int FirstLineMinMs = 60_000;
    public const int FirstLineMaxMs = 120_000;
    public const int MinGapMs = 4 * 60_000;
    public const int MaxGapMs = 8 * 60_000;

    private sealed class Next
    {
        public long At;
        public long LastPlayerReply;
    }

    /// <summary>A player's /group lines are answered at most this often per group.</summary>
    public const int PlayerReplyCooldownMs = 5_000;

    private static readonly ConditionalWeakTable<Group, Next> Groups = new();

    /// <summary>The next gap: a first line soon after the group forms, then every 4-8 minutes.</summary>
    public static long NextGapMs(bool first, Random random) =>
        first ? FirstLineMinMs + random.Next(FirstLineMaxMs - FirstLineMinMs + 1) : MinGapMs + random.Next(MaxGapMs - MinGapMs + 1);

    /// <summary>True when it is this group's turn to hear a line now (and books the next turn).</summary>
    public static bool TakeTurn(object sync, Func<long> get, Action<long> set, long now, Random random, bool known)
    {
        lock (sync)
        {
            if (!known)
            {
                set(now + NextGapMs(true, random));
                return false;
            }
            if (now < get())
                return false;
            set(now + NextGapMs(false, random));
            return true;
        }
    }

    /// <summary>From the bot's ambient chat check: maybe say a group line. True when the bot spoke.</summary>
    public static bool TryGroupLine(GameBot bot)
    {
        if (!AutonomousBotVoices.Enabled || bot?.Group == null || !bot.IsAutonomousWorldBot || bot.IsTemporaryGroupHelper ||
            !bot.IsAlive || bot.InCombat || bot.IsCasting || !AutonomousLivingServer.GroupHasPlayer(bot.Group))
            return false;
        Group group = bot.Group;
        GameLiving[] members = group.GetMembersInTheGroup().ToArray();
        if (members.Any(member => member.IsAlive && member.InCombat))
            return false;
        bool known = Groups.TryGetValue(group, out Next next);
        next ??= Groups.GetValue(group, _ => new Next());
        if (!TakeTurn(next, () => next.At, value => next.At = value, GameLoop.GameLoopTime, Random.Shared, known))
            return false;
        if (!AutonomousBotVoices.TryLine(bot, "group", out VC.Picked picked))
            return false;
        Send(bot, picked.Text, picked.Line?.Invites ?? "");
        if (!string.IsNullOrEmpty(picked.Correction))
            AutonomousLivingServer.Later(bot, 1_200 + Random.Shared.Next(1_400), () => bot.Group == group, () => Send(bot, picked.Correction, remember: false));
        Answer(bot, group, picked);
        return true;
    }

    /// <summary>
    /// The talking update audit: the player dies in a group of gamebots and nobody said a word. Now a groupmate does, a moment
    /// later: one that can rez says it will ("rez coming, dont release"), another "ouch, sorry". Not during a wipe call.
    /// </summary>
    public static void OnPlayerDying(GamePlayer player)
    {
        if (!AutonomousBotVoices.Enabled || player?.Group == null || Random.Shared.NextDouble() >= 0.75)
            return;
        Group group = player.Group;
        GameBot[] mates = group.GetMembersInTheGroup().OfType<GameBot>()
            .Where(mate => mate.IsAutonomousWorldBot && !mate.IsTemporaryGroupHelper && mate.IsAlive)
            .OrderByDescending(mate => mate.ResurrectionSpell != null && mate.ResurrectionSpell.Level <= mate.Level)
            .ThenBy(_ => Random.Shared.Next()).ToArray();
        if (mates.Length == 0)
            return;
        GameBot speaker = mates[0];
        AutonomousLivingServer.Later(speaker, 1_500 + Random.Shared.Next(2_000), () => speaker.Group == group && speaker.IsAlive && !player.IsAlive,
            () =>
            {
                // Not in a wipe, which has its own call; and "ill rez you" only from a bot that will come and do it (review 2026-10-26).
                var members = group.GetMembersInTheGroup();
                if (members.Count(member => member.IsAlive) * 2 < members.Count)
                    return;
                bool willRez = AutonomousBotChatCoordinator.WillComeRez(speaker, player);
                if (AutonomousBotVoices.TryLine(speaker, "combat", out VC.Picked picked, topic: "player_down", relax: true,
                        withoutFlags: willRez ? null : ["can_rez"]))
                    Send(speaker, picked.Text, "none", player.Name);
            });
    }

    /// <summary>
    /// The talking update: a gamebot that joins the player's group says hello in /group a moment later ("hi all, ty for the
    /// inv"), most of the time. Lines of kind lfg, topic join.
    /// </summary>
    public static void OnJoinedPlayerGroup(GameBot bot)
    {
        if (!AutonomousBotVoices.Enabled || bot?.IsAutonomousWorldBot != true || bot.IsTemporaryGroupHelper || Random.Shared.NextDouble() >= 0.75)
            return;
        Group group = bot.Group;
        AutonomousLivingServer.Later(bot, 2_500 + Random.Shared.Next(3_500), () => bot.Group == group && bot.IsAlive && !bot.InCombat, () =>
        {
            if (AutonomousBotVoices.TryLine(bot, "lfg", out VC.Picked picked, topic: "join", relax: true))
                Send(bot, picked.Text, "none");
        });
    }

    /// <summary>A groupmate may pick the line up, as in /faction (a question nearly always, a remark sometimes).</summary>
    private static void Answer(GameBot speaker, Group group, VC.Picked opener)
    {
        string[] chain = VC.AnswerChain(opener.Line.Invites);
        if (chain.Length == 0)
            return;
        GameBot[] mates = group.GetMembersInTheGroup().OfType<GameBot>()
            .Where(mate => mate != speaker && mate.IsAutonomousWorldBot && !mate.IsTemporaryGroupHelper && mate.IsAlive)
            .OrderBy(_ => Random.Shared.Next()).ToArray();
        if (AutonomousBotChatCoordinator.BotReplyCount(opener.Line.Invites, Math.Min(1, mates.Length), Random.Shared) == 0)
            return;
        GameBot mate = mates[0];
        var slots = new Dictionary<string, string>(StringComparer.Ordinal) { ["player"] = speaker.Name };
        foreach (string answers in chain)
        {
            if (!AutonomousBotVoices.TryLine(mate, "reply", out VC.Picked reply, answers: answers, slots: slots,
                    filter: line => AutonomousChatShortTalk.ReplyFits(opener.Text, line.Text)))
                continue;
            int delay = AutonomousBotChatCoordinator.ReplyDelayMs(reply.Text, 0, Random.Shared);
            AutonomousLivingServer.Later(mate, delay, () => mate.Group == group && mate.IsAlive && !mate.InCombat, () => Send(mate, reply.Text));
            return;
        }
    }

    /// <summary>
    /// The player said something in /group: a groupmate answers in /group, as /faction and /say do (live test 2026-10-18:
    /// "hi" and "where to next?" in /group got no answer). Bots that are fighting or casting stay quiet.
    /// </summary>
    public static void OnPlayerGroupChat(GamePlayer player, string message)
    {
        if (player?.Group != null && !string.IsNullOrWhiteSpace(message))
            BotChatTranscript.Player("group", player, message);
        if (!AutonomousBotVoices.Enabled || player?.Group == null || string.IsNullOrWhiteSpace(message))
            return;
        Group group = player.Group;
        GameBot[] mates = group.GetMembersInTheGroup().OfType<GameBot>()
            .Where(mate => mate.IsAutonomousWorldBot && !mate.IsTemporaryGroupHelper && mate.IsAlive && !mate.InCombat && !mate.IsCasting)
            .OrderBy(_ => Random.Shared.Next()).ToArray();
        if (mates.Length == 0)
            return;
        // The talking update: "why?", "ty", a laugh or an answer to a groupmate's question follows on from what was said.
        if (AutonomousBotChatCoordinator.TryThreadReply(player, message, AutonomousChatThreads.GroupChannel(group),
                AutonomousBotChatCoordinator.ThreadScope.Group))
            return;
        Next next = Groups.GetValue(group, _ => new Next());
        lock (next)
        {
            if (next.LastPlayerReply > 0 && GameLoop.GameLoopTime - next.LastPlayerReply < PlayerReplyCooldownMs)
                return;
            next.LastPlayerReply = GameLoop.GameLoopTime;
        }
        GameBot[] named = mates.Where(mate => AutonomousBotChatCoordinator.ContainsMention(message, mate.Name)).ToArray();
        GameBot[] pool = named.Length > 0 ? named : mates;
        // "eithne what spec r u": the name says who it is for (the holdout check).
        if (named.Length > 0 && AutonomousChatThreads.WithoutName(message, named[0].Name) is { Length: > 0 } unnamed)
            message = unnamed;
        if (AutonomousChatKnowledge.TryAnswer(player, message, out string knowledge))
        {
            GameBot answerer = pool[0];
            AutonomousLivingServer.Later(answerer, AutonomousBotChatCoordinator.ReplyDelayMs(knowledge, 0, Random.Shared),
                () => answerer.Group == group && answerer.IsAlive, () => Send(answerer, AutonomousBotVoices.StyleFor(answerer, knowledge), "", player.Name));
            return;
        }
        eAutonomousChatIntent intent = AutonomousChatIntentModel.Predict(message);
        // The talking update audit: "adds!!", "INC", "train coming RUN" in a PvE group drew "im nowhere near the frontier". A
        // groupmate takes the warning ("got it", "on it").
        if (intent == eAutonomousChatIntent.Alarm)
        {
            GameBot heard = pool[0];
            if (AutonomousBotVoices.TryLine(heard, "reply", out VC.Picked ok, answers: "player_headsup", relax: true))
                AutonomousLivingServer.Later(heard, AutonomousBotChatCoordinator.ReplyDelayMs(ok.Text, 0, Random.Shared) / 2,
                    () => heard.Group == group && heard.IsAlive, () => Send(heard, ok.Text, "none", player.Name));
            return;
        }
        // A group is small: one answer, two for a hello or a ding.
        int count = Math.Min(AutonomousBotChatCoordinator.PlayerReplyCount(intent, false, named.Length > 0, pool.Length, Random.Shared),
            intent is eAutonomousChatIntent.Greeting or eAutonomousChatIntent.Ding ? 2 : 1);
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        int due = 0;
        for (int i = 0; i < pool.Length && used.Count < count; i++)
        {
            GameBot mate = pool[i];
            string reply = AutonomousBotChatCoordinator.ReplyToPlayer(mate, player, message);
            if (string.IsNullOrEmpty(reply) || !AutonomousBotChatCoordinator.TryAddDistinctResponse(used, reply, out reply))
                continue;
            due = AutonomousBotChatCoordinator.ReplyDelayMs(reply, due, Random.Shared);
            string text = reply;
            AutonomousLivingServer.Later(mate, due, () => mate.Group == group && mate.IsAlive && !mate.InCombat, () => Send(mate, text, "", player.Name));
        }
    }

    /// <summary>A bot's line in /group. The talking update: remembered in the group's thread (with what it invites, and the
    /// player it answered), so "why?", "ty" and answers to its questions follow on as in /faction.</summary>
    internal static void Send(GameBot bot, string text, string invites = "", string to = null, bool remember = true)
    {
        if (bot.Group != null && AutonomousLivingServer.GroupHasPlayer(bot.Group))
        {
            bot.Group.SendMessageToGroupMembers(bot, text, eChatType.CT_Group, eChatLoc.CL_ChatWindow);
            BotChatTranscript.Bot("group", bot.Name, bot.Realm, text);
            if (remember)
                AutonomousChatThreads.Log.Record(AutonomousChatThreads.GroupChannel(bot.Group), bot.DatabaseID, bot.Name, text, invites,
                    GameLoop.GameLoopTime, to);
        }
    }
}
