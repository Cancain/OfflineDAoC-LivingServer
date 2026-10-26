using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace DOL.GS;

/// <summary>
/// What bots said lately, by channel, so a player's next line can be read as part of a conversation (the talking update).
/// Before it every line stood alone: a player who answered a bot's question got no "ty", a "why?" after a bot's line drew
/// nothing, and a follow-up by tell got "sup". Pure apart from the clock the caller passes in; unit-tested.
/// </summary>
public sealed class ChatThreadLog
{
    public sealed record Said(string Channel, long BotId, string BotName, string Text, string Invites, long At)
    {
        /// <summary>The kind of line it was ("ask", "boast", "news", "chat"...), for follow-ups that fit it.</summary>
        public string Family => AutonomousBotVoiceCorpus.InviteFamily(Invites);
        public bool Asked => Family == "ask" || Text.TrimEnd().EndsWith('?');
    }

    public const int PerChannel = 8;
    private readonly Dictionary<string, List<Said>> _byChannel = new(StringComparer.Ordinal);
    private readonly Dictionary<long, Said> _byBot = new();
    private readonly HashSet<Said> _closed = new();

    public void Record(string channel, long botId, string botName, string text, string invites, long now)
    {
        if (string.IsNullOrEmpty(channel) || string.IsNullOrWhiteSpace(text))
            return;
        var said = new Said(channel, botId, botName, text.Trim(), invites ?? string.Empty, now);
        lock (_byChannel)
        {
            if (!_byChannel.TryGetValue(channel, out var list))
                _byChannel[channel] = list = new List<Said>();
            list.Add(said);
            if (list.Count > PerChannel)
                list.RemoveAt(0);
            if (botId > 0)
                _byBot[botId] = said;
            if (_closed.Count > 200)
                _closed.Clear();
        }
    }

    /// <summary>The last bot line in the channel within the time, or null.</summary>
    public Said Last(string channel, long now, long withinMs)
    {
        lock (_byChannel)
            return _byChannel.TryGetValue(channel, out var list) && list.Count > 0 && now - list[^1].At <= withinMs ? list[^1] : null;
    }

    /// <summary>The last line this bot said anywhere within the time, or null.</summary>
    public Said LastBy(long botId, long now, long withinMs)
    {
        lock (_byChannel)
            return _byBot.TryGetValue(botId, out Said said) && now - said.At <= withinMs ? said : null;
    }

    /// <summary>
    /// The question a player's line may be answering: the last line in the channel, if it asked something within the time
    /// and nobody has answered it yet (an answer closes it).
    /// </summary>
    public Said OpenQuestion(string channel, long now, long withinMs)
    {
        Said last = Last(channel, now, withinMs);
        lock (_byChannel)
            return last != null && last.Asked && !_closed.Contains(last) ? last : null;
    }

    public void Close(Said said)
    {
        if (said == null)
            return;
        lock (_byChannel)
            _closed.Add(said);
    }
}

public static class AutonomousChatThreads
{
    public static readonly ChatThreadLog Log = new();

    /// <summary>How long a bot's line stays the one a player's "why?" or answer is about.</summary>
    public const long FollowUpWindowMs = 90_000;
    public const long AnswerWindowMs = 75_000;
    public const long TellMemoryMs = 4 * 60_000;

    public static string Faction(eRealm realm) => "faction:" + realm;
    public static string Say(ushort region) => "say:" + region;
    public static string Tell(string player, string bot) => "tell:" + player + "|" + bot;
    public static string GroupChannel(object group) => group == null ? null : "group:" + System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(group);

    private static readonly (Regex Pattern, string Word)[] FollowUps =
    [
        (new Regex(@"^(why|y|why\s?not|how come|whys that|why is that|why tho|why though|how so)$"), "why"),
        (new Regex(@"^(really|rly|srsly|seriously|for real|no way|are you sure|u sure|you sure|honestly|truly)$"), "really"),
        (new Regex(@"^(how|how do you mean|how do u mean|how do you do that|how did you|how'd you|hows that work|how does that work)$"), "how"),
        (new Regex(@"^(what|wut|wat|huh|what do you mean|what do u mean|wdym|meaning|what about it|what is that|whats that)$"), "what"),
        (new Regex(@"^(who|who was it|who did|who said|who is that|whos that|who was that)$"), "who"),
        (new Regex(@"^(where|where at|where is that|wheres that|where exactly|where is it|wheres it|where abouts|whereabouts)$"), "where"),
    ];

    /// <summary>"why?", "rly?", "how so", "where at?": a short follow-up to the last thing said, or null.</summary>
    public static string FollowUpWord(string message)
    {
        if (string.IsNullOrWhiteSpace(message))
            return null;
        string text = Regex.Replace(message.ToLowerInvariant(), @"[^a-z' ]", " ");
        text = Regex.Replace(text, @"\s+", " ").Trim();
        if (text.Length == 0 || text.Split(' ').Length > 5)
            return null;
        foreach ((Regex pattern, string word) in FollowUps)
            if (pattern.IsMatch(text))
                return word;
        return null;
    }

    /// <summary>
    /// Whether a player's line reads as an answer to a bot's question: not a question itself, not a greeting, laugh or
    /// goodbye, and with some words in it ("try spindel", "no idea sorry", "yeah im in").
    /// </summary>
    public static bool ReadsAsAnswer(string message, eAutonomousChatIntent intent)
    {
        if (string.IsNullOrWhiteSpace(message) || message.Contains('?') || FollowUpWord(message) != null)
            return false;
        if (intent is eAutonomousChatIntent.Greeting or eAutonomousChatIntent.Farewell or eAutonomousChatIntent.Laugh or
            eAutonomousChatIntent.Away or eAutonomousChatIntent.Back or eAutonomousChatIntent.Abuse or eAutonomousChatIntent.IgnoreOutOfWorld or
            eAutonomousChatIntent.Ding or eAutonomousChatIntent.Alarm or eAutonomousChatIntent.Rez)
            return false;
        return Regex.Matches(message, @"[A-Za-z]{2,}").Count >= 1;
    }

    private static readonly Regex Yes = new(@"^(sure|yes|yeah|yea|ya|yep|yup|ok|okay|k|kk|ok sure|sure thing|why not|sounds good|lets go|let's go|lets do it|let's do it|definitely|absolutely|of course|ofc|inv|invite|inv me|np|sure why not|go for it|im in|i'm in|deal|sweet|cool)\b");
    private static readonly Regex No = new(@"^(no|nah|nope|no thanks|no thx|no ty|not now|not right now|maybe later|later|im good|i'm good|im ok|i'm ok|pass|cant|can't|sorry|busy|already grouped|im grouped|i'm grouped)\b");

    /// <summary>"sure", "yeah inv me", "ok": a yes to an offer. "nah", "maybe later": a no. Null when neither.</summary>
    public static bool? SaysYes(string message)
    {
        if (string.IsNullOrWhiteSpace(message))
            return null;
        string text = Regex.Replace(message.ToLowerInvariant(), @"[^a-z' ]", " ");
        text = Regex.Replace(text, @"\s+", " ").Trim();
        if (No.IsMatch(text))
            return false;
        return Yes.IsMatch(text) ? true : null;
    }

    /// <summary>The closing sets that fit the question asked, most specific first ("ask_where" then "ask").</summary>
    public static string[] ClosingAnswers(string invites)
    {
        string family = AutonomousBotVoiceCorpus.InviteFamily(invites);
        if (string.IsNullOrEmpty(invites))
            return ["ask"];
        return invites == family ? [invites] : [invites, family];
    }
}
