using System.Data.SQLite;
using System.Globalization;
using DOL.GS;

namespace OfflineDaoc.Launcher;

/// <summary>
/// The Social Expansion's server settings (docs/BOT-GUILDS.md, docs/BOT-PERSONALITIES.md,
/// docs/XP-BY-LEVEL-RANGE.md), read from and written to the world database's ServerProperty table,
/// as the launcher's Options tab does for the flat XP rates. The server reads them at startup.
/// A setting without a row uses the server's default, which is the default here too.
/// </summary>
public sealed record SocialExpansionSettings
{
    public const string SuggestedPlayerXp = "1-19:3;20-34:5;35-50:12";
    public const string SuggestedBotXp = "1-19:1.5;20-34:2.5;35-50:6";

    public bool BotGuilds { get; init; }
    public int GuildSharePercent { get; init; } = 70;
    public int GuildMinLevel { get; init; } = 5;
    public bool GuildSocial { get; init; } = true;
    public bool GuildRecruitPlayer { get; init; } = true;
    public bool GuildClaims { get; init; } = true;
    public bool GuildEconomy { get; init; } = true;
    public bool GuildAlliances { get; init; } = true;
    public bool Personalities { get; init; }
    public bool Voices { get; init; }
    public bool Debates { get; init; } = true;
    public string PlayerXpByLevel { get; init; } = "";
    public string BotXpByLevel { get; init; } = "";

    /// <summary>The server's defaults: every Social Expansion feature off.</summary>
    public static SocialExpansionSettings Defaults { get; } = new();

    // Key, category and description of each setting, as the server and the Python helpers write them.
    internal static readonly (string Key, string Category, string Description)[] Settings =
    [
        ("bot_guilds_enabled", "guild", "Autonomous gamebots form and join realm guilds (see docs/BOT-GUILDS.md), and players can /ginvite them. False keeps every gamebot guildless; saved memberships are kept."),
        ("bot_guild_share", "guild", "Share (0 to 1) of eligible autonomous gamebots that bot guild formation places in guilds."),
        ("bot_guild_min_level", "guild", "Lowest level at which an autonomous gamebot is placed in a bot guild."),
        ("bot_guild_social", "guild", "When bot guilds are on: guild members greet, congratulate and chat in guild chat when a real member can hear, answer your /gu, and bot guild officers recruit in /faction."),
        ("bot_guild_recruit_player", "guild", "When bot guild social life is on: bot guild officers may invite you to their guild with a yes/no dialog."),
        ("bot_guild_claims_keeps", "guild", "When bot guilds are on: bot guilds claim keeps and towers their realm takes, and defend them first."),
        ("bot_guild_economy", "guild", "When bot guilds are on: guilded gamebots pay dues from real loot, level-ups earn merit points, and leaders buy guild buffs."),
        ("bot_guild_alliances", "guild", "When bot guilds are on: each realm's RvR and raiding bot guilds form one alliance."),
        ("bot_personalities_enabled", "bots", "Autonomous gamebots get a personality and traits that tilt town breaks, goals, dungeons, camps and chattiness (see docs/BOT-PERSONALITIES.md)."),
        ("bot_voices_enabled", "bots", "Autonomous gamebots say pre-written, period lines in their own writing style (docs/bot-voices/DESIGN.md)."),
        ("bot_voices_debates", "bots", "When bot voices are on: bots of a realm play debates and long threads in /faction while you are online."),
        ("xp_rate_by_level", "rates", "Optional XP rate by level range for real player characters (set in the launcher's Social Expansion tab)."),
        ("bot_xp_rate_by_level", "rates", "Optional XP rate by level range for autonomous gamebots (set in the launcher's Social Expansion tab)."),
    ];

    /// <summary>The value the server would read for each key.</summary>
    public IReadOnlyDictionary<string, string> ToStoredValues() => new Dictionary<string, string>
    {
        ["bot_guilds_enabled"] = Bool(BotGuilds),
        ["bot_guild_share"] = (GuildSharePercent / 100.0).ToString("0.##", CultureInfo.InvariantCulture),
        ["bot_guild_min_level"] = GuildMinLevel.ToString(CultureInfo.InvariantCulture),
        ["bot_guild_social"] = Bool(GuildSocial),
        ["bot_guild_recruit_player"] = Bool(GuildRecruitPlayer),
        ["bot_guild_claims_keeps"] = Bool(GuildClaims),
        ["bot_guild_economy"] = Bool(GuildEconomy),
        ["bot_guild_alliances"] = Bool(GuildAlliances),
        ["bot_personalities_enabled"] = Bool(Personalities),
        ["bot_voices_enabled"] = Bool(Voices),
        ["bot_voices_debates"] = Bool(Debates),
        ["xp_rate_by_level"] = PlayerXpByLevel.Trim(),
        ["bot_xp_rate_by_level"] = BotXpByLevel.Trim(),
    };

    private static string Bool(bool value) => value ? "True" : "False";

    /// <summary>
    /// Settings from stored values (missing keys keep the server default). A stored value the server can't read
    /// shows what the server then uses (its fields stay at zero: False, 0), and a share above 1 shows as 100%;
    /// each is reported in <paramref name="problems"/> and its key added to <paramref name="problemKeys"/>, so a
    /// save can repair exactly those rows.
    /// </summary>
    public static SocialExpansionSettings FromStoredValues(IReadOnlyDictionary<string, string?> stored, List<string> problems,
        ISet<string>? problemKeys = null)
    {
        var d = Defaults;
        void Problem(string key, string message)
        {
            problems.Add(message);
            problemKeys?.Add(key);
        }
        bool ReadBool(string key, bool fallback)
        {
            if (!stored.TryGetValue(key, out string? text) || string.IsNullOrWhiteSpace(text)) return fallback;
            if (bool.TryParse(text.Trim(), out bool value)) return value;
            Problem(key, $"{key} = \"{text}\" is not True or False, so the server reads it as False.");
            return false;
        }
        int share = d.GuildSharePercent;
        if (stored.TryGetValue("bot_guild_share", out string? shareText) && !string.IsNullOrWhiteSpace(shareText))
        {
            if (!double.TryParse(shareText.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out double fraction))
            {
                Problem("bot_guild_share", $"bot_guild_share = \"{shareText}\" is not a number, so the server reads it as 0.");
                share = 0;
            }
            else if (fraction < 0 || fraction > 1)
            {
                Problem("bot_guild_share", $"bot_guild_share = \"{shareText}\" is outside 0 to 1.");
                share = fraction < 0 ? 0 : 100;
            }
            else
                share = (int)Math.Round(fraction * 100, MidpointRounding.AwayFromZero);
        }
        int minLevel = d.GuildMinLevel;
        if (stored.TryGetValue("bot_guild_min_level", out string? levelText) && !string.IsNullOrWhiteSpace(levelText))
        {
            if (!int.TryParse(levelText.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int level))
            {
                Problem("bot_guild_min_level", $"bot_guild_min_level = \"{levelText}\" is not a whole number, so the server reads it as 0.");
                minLevel = 0;
            }
            else if (level < 0 || level > 50)
            {
                Problem("bot_guild_min_level", $"bot_guild_min_level = \"{levelText}\" is outside 0 to 50.");
                minLevel = Math.Clamp(level, 0, 50);
            }
            else
                minLevel = level;
        }
        return new SocialExpansionSettings
        {
            BotGuilds = ReadBool("bot_guilds_enabled", d.BotGuilds),
            GuildSharePercent = share,
            GuildMinLevel = minLevel,
            GuildSocial = ReadBool("bot_guild_social", d.GuildSocial),
            GuildRecruitPlayer = ReadBool("bot_guild_recruit_player", d.GuildRecruitPlayer),
            GuildClaims = ReadBool("bot_guild_claims_keeps", d.GuildClaims),
            GuildEconomy = ReadBool("bot_guild_economy", d.GuildEconomy),
            GuildAlliances = ReadBool("bot_guild_alliances", d.GuildAlliances),
            Personalities = ReadBool("bot_personalities_enabled", d.Personalities),
            Voices = ReadBool("bot_voices_enabled", d.Voices),
            Debates = ReadBool("bot_voices_debates", d.Debates),
            // Kept as written: an invalid range setting shows its own error in the tab (the server ignores it).
            PlayerXpByLevel = stored.TryGetValue("xp_rate_by_level", out string? player) ? player?.Trim() ?? "" : "",
            BotXpByLevel = stored.TryGetValue("bot_xp_rate_by_level", out string? bots) ? bots?.Trim() ?? "" : "",
        };
    }

    /// <summary>
    /// "All off": the three features and both XP ranges off. The share, lowest level and each part keep their
    /// values, so turning a feature back on later restores the player's own choices.
    /// </summary>
    public SocialExpansionSettings AllOff() => this with
    {
        BotGuilds = false, Personalities = false, Voices = false, PlayerXpByLevel = "", BotXpByLevel = "",
    };

    /// <summary>True when every feature and both XP ranges are off.</summary>
    public bool IsAllOff => !BotGuilds && !Personalities && !Voices && PlayerXpByLevel.Trim() == "" && BotXpByLevel.Trim() == "";

    /// <summary>Why these settings can't be saved, or null when they can.</summary>
    public string? Validate()
    {
        if (GuildSharePercent is < 0 or > 100) return "The share of bots in guilds must be 0 to 100%.";
        if (GuildMinLevel is < 0 or > 50) return "The lowest guild level must be 0 to 50.";
        return XpError("Your XP by level", PlayerXpByLevel) ?? XpError("Bot XP by level", BotXpByLevel);
    }

    /// <summary>Why an XP-by-level setting is invalid (the server's own rules), or null when it is empty or valid.</summary>
    public static string? XpError(string label, string spec)
    {
        if (string.IsNullOrWhiteSpace(spec)) return null;
        return LevelRangeXpRates.TryParse(spec, out _, out string error) ? null : $"{label}: {error}.";
    }

    public static SocialExpansionSettings Load(string database, List<string> problems, ISet<string>? problemKeys = null)
    {
        if (!File.Exists(database)) throw new InvalidOperationException("The world database is missing: " + database);
        using var connection = Open(database, readOnly: true);
        return FromStoredValues(ReadStored(connection, null), problems, problemKeys);
    }

    /// <summary>
    /// Writes the settings that differ from <paramref name="previous"/> (all of them when it is null) and the keys in
    /// <paramref name="alsoWrite"/> (rows being repaired), in one transaction, then reads them back. Only while the
    /// server is stopped.
    /// </summary>
    public void Save(string database, SocialExpansionSettings? previous, Func<bool> serverStopped, IEnumerable<string>? alsoWrite = null)
    {
        if (Validate() is { } invalid) throw new InvalidOperationException(invalid);
        if (!serverStopped()) throw new InvalidOperationException("Stop the server first. Settings can only change while it is stopped.");
        if (!File.Exists(database)) throw new InvalidOperationException("The world database is missing: " + database);
        var values = ToStoredValues();
        var old = previous?.ToStoredValues();
        var repair = new HashSet<string>(alsoWrite ?? Array.Empty<string>(), StringComparer.Ordinal);
        var changed = values.Where(pair => old is null || old[pair.Key] != pair.Value || repair.Contains(pair.Key))
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        if (changed.Count == 0) return;

        using var connection = Open(database, readOnly: false);
        using (var transaction = connection.BeginTransaction())
        {
            string updated = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture);
            foreach (var (key, value) in changed)
            {
                var setting = Settings.Single(s => s.Key == key);
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                // ServerProperty_ID is unique, so new rows use the key, as the server's own rows do.
                command.CommandText = """
                    INSERT INTO ServerProperty (Category, `Key`, Description, DefaultValue, Value, LastTimeRowUpdated, ServerProperty_ID)
                    VALUES (@category, @key, @description, '', @value, @updated, @key)
                    ON CONFLICT(`Key`) DO UPDATE SET Value=excluded.Value, LastTimeRowUpdated=excluded.LastTimeRowUpdated
                    """;
                command.Parameters.AddWithValue("@category", setting.Category);
                command.Parameters.AddWithValue("@key", key);
                command.Parameters.AddWithValue("@description", setting.Description);
                command.Parameters.AddWithValue("@value", value);
                command.Parameters.AddWithValue("@updated", updated);
                command.ExecuteNonQuery();
            }
            transaction.Commit();
        }
        var after = ReadStored(connection, changed.Keys);
        foreach (var (key, value) in changed)
        {
            if ((after.GetValueOrDefault(key) ?? "") != value)
                throw new InvalidOperationException($"{key} reads back as \"{after.GetValueOrDefault(key)}\", not \"{value}\".");
        }
    }

    private static SQLiteConnection Open(string database, bool readOnly)
    {
        var builder = new SQLiteConnectionStringBuilder { DataSource = database, Pooling = false, DefaultTimeout = 10, ReadOnly = readOnly };
        var connection = new SQLiteConnection(builder.ConnectionString);
        connection.Open();
        return connection;
    }

    private static Dictionary<string, string?> ReadStored(SQLiteConnection connection, IEnumerable<string>? keys)
    {
        var wanted = (keys ?? Settings.Select(s => s.Key)).ToArray();
        using var command = connection.CreateCommand();
        command.CommandText = $"SELECT `Key`, Value FROM ServerProperty WHERE `Key` IN ({string.Join(",", wanted.Select((_, i) => "@k" + i))})";
        for (int i = 0; i < wanted.Length; i++) command.Parameters.AddWithValue("@k" + i, wanted[i]);
        var stored = new Dictionary<string, string?>(StringComparer.Ordinal);
        using var reader = command.ExecuteReader();
        while (reader.Read()) stored[reader.GetString(0)] = reader.IsDBNull(1) ? null : reader.GetString(1);
        return stored;
    }
}
