using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace DOL.GS;

/// <summary>
/// The bot-voices corpus (docs/bot-voices/DESIGN.md): pre-written, era-checked lines and scenes,
/// built by tools/bot-voices/build_corpus.py into corpus.json, plus the writing styles in
/// voices.json. Pure: parsing, filtering, slot filling, styles and the no-repeat window, with no
/// game objects, so all of it is unit-tested. Nothing is generated freely.
/// </summary>
public sealed class AutonomousBotVoiceCorpus
{
    public const int MaxLength = 160;

    public sealed record Line(string Id, string Kind, string Topic, string[] Who, string Realm, string[] Classes,
        int LevelLow, int LevelHigh, string[] Needs, string Intent, string Mood, double Weight, string Text);

    public sealed record Beat(string Role, string[] Variants, bool Optional, int PauseSeconds)
    {
        public bool IsPause => Role == "~";
    }

    public sealed record RoleSpec(string[] Types, string[] Classes);

    public sealed record Scene(string Id, string Topic, string Realm, int LevelLow, int LevelHigh,
        IReadOnlyDictionary<string, RoleSpec> Roles, Beat[] Beats)
    {
        public string[] SpeakingRoles => Beats.Where(beat => !beat.IsPause).Select(beat => beat.Role).Distinct().ToArray();
    }

    public sealed record Voice(string Name, double Share, bool Capitalize, bool CapitalizeSentences, bool EndPeriod,
        string[] NoPeriodAfter, bool StripPunctuation, (string From, string To)[] Abbreviate,
        IReadOnlyDictionary<string, string> Expand, string[] Emotes, double EmoteChance, double TypoChance);

    /// <summary>Who is speaking, as plain values (built from a live bot by AutonomousBotVoices).</summary>
    public sealed record Speaker(long Id, string Name, eRealm Realm, string ClassName, int Level, BotPersonalityType Type,
        IReadOnlySet<string> Flags);

    public Line[] Lines { get; }
    public Scene[] Scenes { get; }
    public Voice[] Voices { get; }

    private AutonomousBotVoiceCorpus(Line[] lines, Scene[] scenes, Voice[] voices)
    {
        Lines = lines;
        Scenes = scenes;
        Voices = voices;
    }

    #region Parsing

    public static AutonomousBotVoiceCorpus Parse(string corpusJson, string voicesJson)
    {
        using JsonDocument corpus = JsonDocument.Parse(corpusJson);
        using JsonDocument voices = JsonDocument.Parse(voicesJson);
        var lines = corpus.RootElement.GetProperty("lines").EnumerateArray().Select(ParseLine).ToArray();
        var scenes = corpus.RootElement.GetProperty("scenes").EnumerateArray().Select(ParseScene).ToArray();
        var styles = voices.RootElement.GetProperty("voices").EnumerateObject().Select(ParseVoice).ToArray();
        if (styles.Length == 0 || styles.Sum(voice => voice.Share) <= 0)
            throw new InvalidOperationException("voices.json has no usable voices");
        return new AutonomousBotVoiceCorpus(lines, scenes, styles);
    }

    private static string Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? string.Empty : string.Empty;

    private static string[] Strs(JsonElement e, string name) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Array
            ? v.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString())
                .Where(x => !string.IsNullOrEmpty(x) && x != "*").ToArray()
            : Array.Empty<string>();

    private static (int, int) Levels(JsonElement e)
    {
        if (e.TryGetProperty("levels", out JsonElement v) && v.ValueKind == JsonValueKind.Array && v.GetArrayLength() == 2)
            return (v[0].GetInt32(), v[1].GetInt32());
        return (1, 50);
    }

    private static double Num(JsonElement e, string name, double fallback) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : fallback;

    private static bool Bool(JsonElement e, string name) =>
        e.TryGetProperty(name, out JsonElement v) && v.ValueKind == JsonValueKind.True;

    private static Line ParseLine(JsonElement e)
    {
        (int low, int high) = Levels(e);
        string realm = Str(e, "realm");
        return new Line(Str(e, "id"), Str(e, "kind"), Str(e, "topic"), Strs(e, "who"), realm.Length == 0 ? "*" : realm,
            Strs(e, "class"), low, high, Strs(e, "needs"), Str(e, "intent"), Str(e, "mood"), Num(e, "weight", 1.0), Str(e, "text"));
    }

    private static Scene ParseScene(JsonElement e)
    {
        (int low, int high) = Levels(e);
        var roles = new Dictionary<string, RoleSpec>(StringComparer.Ordinal);
        if (e.TryGetProperty("roles", out JsonElement r) && r.ValueKind == JsonValueKind.Object)
            foreach (JsonProperty role in r.EnumerateObject())
                roles[role.Name] = new RoleSpec(Strs(role.Value, "type"), Strs(role.Value, "class"));
        var beats = e.GetProperty("beats").EnumerateArray().Select(b =>
        {
            string role = Str(b, "role");
            string[] variants = Strs(b, "variants");
            if (variants.Length == 0 && Str(b, "text").Length > 0)
                variants = new[] { Str(b, "text") };
            return new Beat(role, variants, Bool(b, "optional"), (int)Num(b, "pause", 0));
        }).ToArray();
        string realm = Str(e, "realm");
        return new Scene(Str(e, "id"), Str(e, "topic"), realm.Length == 0 ? "*" : realm, low, high, roles, beats);
    }

    private static Voice ParseVoice(JsonProperty p)
    {
        JsonElement e = p.Value;
        var abbreviate = e.TryGetProperty("abbreviate", out JsonElement a) && a.ValueKind == JsonValueKind.Object
            ? a.EnumerateObject().Select(x => (x.Name, x.Value.GetString() ?? string.Empty))
                .OrderByDescending(x => x.Name.Length).ToArray()   // longer phrases first
            : Array.Empty<(string, string)>();
        var expand = new Dictionary<string, string>(StringComparer.Ordinal);
        if (e.TryGetProperty("expand", out JsonElement x2) && x2.ValueKind == JsonValueKind.Object)
            foreach (JsonProperty pair in x2.EnumerateObject())
                expand[pair.Name] = pair.Value.GetString() ?? string.Empty;
        return new Voice(p.Name, Num(e, "share", 0), Bool(e, "capitalize"), Bool(e, "capitalize_sentences"), Bool(e, "end_period"),
            Strs(e, "no_period_after"), Bool(e, "strip_punctuation"), abbreviate, expand, Strs(e, "emotes"),
            Num(e, "emote_chance", 0), Num(e, "typo_chance", 0));
    }

    #endregion

    #region Choosing

    public static string RealmCode(eRealm realm) => realm switch
    {
        eRealm.Albion => "alb",
        eRealm.Midgard => "mid",
        eRealm.Hibernia => "hib",
        _ => "*",
    };

    public static bool RealmFits(string lineRealm, eRealm realm) => lineRealm == "*" || lineRealm == RealmCode(realm);

    public static bool ClassFits(string[] classes, string className) =>
        classes.Length == 0 || classes.Any(c => string.Equals(c, className, StringComparison.OrdinalIgnoreCase));

    public static bool TypeFits(string[] types, BotPersonalityType type) =>
        types.Length == 0 || types.Any(t => string.Equals(t, type.ToString(), StringComparison.OrdinalIgnoreCase));

    /// <summary>Lines of a kind this speaker may say now (realm, class, level band, needed context, intent).</summary>
    public IEnumerable<Line> Candidates(string kind, Speaker speaker, string intent = null, string topic = null) =>
        Lines.Where(line => line.Kind == kind &&
                            (topic == null || string.Equals(line.Topic, topic, StringComparison.Ordinal)) &&
                            RealmFits(line.Realm, speaker.Realm) &&
                            ClassFits(line.Classes, speaker.ClassName) &&
                            speaker.Level >= line.LevelLow && speaker.Level <= line.LevelHigh &&
                            line.Needs.All(need => speaker.Flags.Contains(need)) &&
                            (string.IsNullOrEmpty(intent) || string.Equals(line.Intent, intent, StringComparison.OrdinalIgnoreCase)));

    /// <summary>A line's draw weight for this speaker: lines written for its personality type count triple.</summary>
    public static double WeightFor(Line line, Speaker speaker) =>
        Math.Max(0.01, line.Weight) * (line.Who.Length > 0 && TypeFits(line.Who, speaker.Type) ? 3.0 : line.Who.Length > 0 ? 0.0 : 1.0);

    /// <summary>
    /// Picks, fills and styles a line, skipping lines heard in this realm recently and lines whose
    /// slots can't be filled. False when nothing fits (the caller keeps its old line).
    /// </summary>
    public bool TryPick(string kind, Speaker speaker, IReadOnlyDictionary<string, string> slots, RecentLines recent,
        DateTime now, Random random, out string text, out string lineId, string intent = null, string topic = null)
    {
        text = null;
        lineId = null;
        var pool = Candidates(kind, speaker, intent, topic)
            .Where(line => recent == null || !recent.WasUsed(speaker.Realm, line.Id, now))
            .Select(line => (Line: line, Weight: WeightFor(line, speaker)))
            .Where(entry => entry.Weight > 0)
            .ToList();
        while (pool.Count > 0)
        {
            double total = pool.Sum(entry => entry.Weight);
            double draw = random.NextDouble() * total;
            int index = 0;
            for (; index < pool.Count - 1; index++)
            {
                if (draw < pool[index].Weight)
                    break;
                draw -= pool[index].Weight;
            }
            Line line = pool[index].Line;
            pool.RemoveAt(index);
            if (!TryFill(line.Text, slots, out string filled))
                continue;
            text = Style(filled, VoiceFor(speaker.Id), random);
            lineId = line.Id;
            recent?.Use(speaker.Realm, line.Id, now);
            return true;
        }
        return false;
    }

    #endregion

    #region Slots

    private static readonly Regex SlotPattern = new(@"\{(\w+)\}", RegexOptions.CultureInvariant);

    /// <summary>Optional openers for {q}; empty half the time.</summary>
    public static readonly string[] Openers = ["", "", "", "hey", "so", "random question but", "quick question,", "ok so"];

    /// <summary>Fills every {slot}; false if any slot has no value (a line is never sent half-filled).</summary>
    public static bool TryFill(string template, IReadOnlyDictionary<string, string> slots, out string filled)
    {
        bool ok = true;
        string result = SlotPattern.Replace(template ?? string.Empty, match =>
        {
            if (slots != null && slots.TryGetValue(match.Groups[1].Value, out string value) && value != null &&
                (value.Length > 0 || match.Groups[1].Value == "q"))
                return value;
            ok = false;
            return match.Value;
        });
        filled = ok ? Regex.Replace(result, @"\s+", " ").Trim().TrimStart(',', ' ') : null;
        return ok && !string.IsNullOrEmpty(filled);
    }

    #endregion

    #region Voices

    /// <summary>A bot's writing style, fixed from its id by the styles' shares.</summary>
    public Voice VoiceFor(long botId)
    {
        double total = Voices.Sum(voice => voice.Share);
        double draw = AutonomousBotPersonality.Mix(botId, 2) % 1_000_000 / 1_000_000.0 * total;
        foreach (Voice voice in Voices)
        {
            if (draw < voice.Share)
                return voice;
            draw -= voice.Share;
        }
        return Voices[^1];
    }

    /// <summary>Applies a writing style (the server version of tools/bot-voices/preview.py's voice_apply).</summary>
    public static string Style(string text, Voice voice, Random random)
    {
        if (string.IsNullOrEmpty(text) || voice == null)
            return text;
        string result = text;
        foreach ((string from, string to) in voice.Abbreviate)
            result = Regex.Replace(result, $@"(?<=^|\s){Regex.Escape(from)}(?=$|[\s,.?!])", to, RegexOptions.CultureInvariant);
        if (voice.Expand.Count > 0)
            result = string.Join(' ', result.Split(' ').Select(word => voice.Expand.TryGetValue(word, out string full) ? full : word));
        if (voice.StripPunctuation)
            result = result.TrimEnd('.', '!').Replace(",", string.Empty);
        if (voice.TypoChance > 0 && random.NextDouble() < voice.TypoChance)
            result = SwapTypo(result, random);
        if (voice.Emotes.Length > 0 && voice.EmoteChance > 0 && random.NextDouble() < voice.EmoteChance)
            result += " " + voice.Emotes[random.Next(voice.Emotes.Length)];
        if (voice.Capitalize && result.Length > 0)
            result = char.ToUpperInvariant(result[0]) + result[1..];
        if (voice.CapitalizeSentences)
            result = Regex.Replace(result, @"([.!?] )([a-z])", m => m.Groups[1].Value + m.Groups[2].Value.ToUpperInvariant());
        if (voice.EndPeriod && result.Length > 0)
        {
            string[] after = voice.NoPeriodAfter.Length > 0 ? voice.NoPeriodAfter : new[] { ".", "!", "?" };
            if (!after.Any(end => result.EndsWith(end, StringComparison.Ordinal)))
                result += ".";
        }
        return result.Length <= MaxLength ? result : result[..MaxLength];
    }

    /// <summary>Swaps two neighboring letters in one word of four or more letters.</summary>
    public static string SwapTypo(string text, Random random)
    {
        string[] words = text.Split(' ');
        int[] eligible = words.Select((word, index) => (word, index))
            .Where(x => x.word.Length >= 4 && x.word.All(char.IsLetter)).Select(x => x.index).ToArray();
        if (eligible.Length == 0)
            return text;
        int pick = eligible[random.Next(eligible.Length)];
        char[] letters = words[pick].ToCharArray();
        int at = random.Next(letters.Length - 1);
        (letters[at], letters[at + 1]) = (letters[at + 1], letters[at]);
        words[pick] = new string(letters);
        return string.Join(' ', words);
    }

    #endregion

    #region No-repeat window

    /// <summary>
    /// When each line was last used in each realm, kept for <see cref="Window"/>. The capacity is far
    /// above the corpus size, so a line really is not repeated in a realm within the window (audit
    /// 2026-10-16: a 400-entry list could let a busy realm repeat lines after an hour or two).
    /// </summary>
    public sealed class RecentLines
    {
        public static readonly TimeSpan Window = TimeSpan.FromHours(6);
        public const int Capacity = 5000;
        private readonly Dictionary<eRealm, Dictionary<string, DateTime>> _byRealm = new();

        public bool WasUsed(eRealm realm, string id, DateTime now)
        {
            lock (_byRealm)
                return _byRealm.TryGetValue(realm, out var used) && used.TryGetValue(id, out DateTime when) && now - when < Window;
        }

        public void Use(eRealm realm, string id, DateTime now)
        {
            lock (_byRealm)
            {
                if (!_byRealm.TryGetValue(realm, out var used))
                    _byRealm[realm] = used = new Dictionary<string, DateTime>(StringComparer.Ordinal);
                used[id] = now;
                if (used.Count <= Capacity)
                    return;
                foreach (string old in used.Where(entry => now - entry.Value >= Window).Select(entry => entry.Key).ToList())
                    used.Remove(old);
                foreach (string oldest in used.OrderBy(entry => entry.Value).Take(used.Count - Capacity).Select(entry => entry.Key).ToList())
                    used.Remove(oldest);
            }
        }

        public int Count(eRealm realm)
        {
            lock (_byRealm)
                return _byRealm.TryGetValue(realm, out var used) ? used.Count : 0;
        }
    }

    #endregion
}
