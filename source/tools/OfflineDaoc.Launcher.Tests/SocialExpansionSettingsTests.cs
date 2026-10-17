using System.Data.SQLite;
using System.Reflection;
using System.Text.RegularExpressions;
using NUnit.Framework;
using OfflineDaoc.Launcher;

[TestFixture, NonParallelizable, Apartment(ApartmentState.STA)]
public class SocialExpansionSettingsTests
{
    private string _folder = null!, _database = null!;
    private bool _stopped;
    private const BindingFlags Hidden = BindingFlags.Instance | BindingFlags.NonPublic;

    [SetUp] public void Setup()
    {
        _folder = Path.Combine(Path.GetTempPath(), "social-expansion-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
        _database = Path.Combine(_folder, "opendaoc.sqlite3.db");
        _stopped = true;
        // The world database's ServerProperty table: Key is the primary key and ServerProperty_ID is unique.
        Exec("""
            CREATE TABLE ServerProperty (Category TEXT NOT NULL, `Key` TEXT NOT NULL PRIMARY KEY, Description TEXT NOT NULL,
                DefaultValue TEXT NOT NULL, Value TEXT NOT NULL, LastTimeRowUpdated TEXT, ServerProperty_ID TEXT NOT NULL UNIQUE);
            INSERT INTO ServerProperty VALUES ('rates', 'xp_rate', 'flat', '1', '1', '', '');
            """);
    }

    [TearDown] public void Cleanup()
    {
        SQLiteConnection.ClearAllPools();
        if (Directory.Exists(_folder)) Directory.Delete(_folder, true);
    }

    private void Exec(string sql)
    {
        using var c = new SQLiteConnection($"Data Source={_database};Pooling=False");
        c.Open();
        using var command = c.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private Dictionary<string, string> Rows()
    {
        using var c = new SQLiteConnection($"Data Source={_database};Pooling=False");
        c.Open();
        using var command = c.CreateCommand();
        command.CommandText = "SELECT `Key`, Value FROM ServerProperty";
        using var reader = command.ExecuteReader();
        var rows = new Dictionary<string, string>();
        while (reader.Read()) rows[reader.GetString(0)] = reader.GetString(1);
        return rows;
    }

    private static readonly SocialExpansionSettings AllOn = new()
    {
        BotGuilds = true, GuildSharePercent = 60, GuildMinLevel = 10, Personalities = true, Voices = true,
        GuildAlliances = false, PlayerXpByLevel = SocialExpansionSettings.SuggestedPlayerXp,
        BotXpByLevel = SocialExpansionSettings.SuggestedBotXp,
    };

    [Test] public void NoRowsMeansTheServerDefaultsEverythingOff()
    {
        var problems = new List<string>();
        Assert.That(SocialExpansionSettings.Load(_database, problems), Is.EqualTo(SocialExpansionSettings.Defaults));
        Assert.That(problems, Is.Empty);
        Assert.That(SocialExpansionSettings.Defaults.BotGuilds || SocialExpansionSettings.Defaults.Personalities ||
                    SocialExpansionSettings.Defaults.Voices, Is.False);
        Assert.That(SocialExpansionSettings.Defaults.PlayerXpByLevel + SocialExpansionSettings.Defaults.BotXpByLevel, Is.Empty);
    }

    [Test] public void SaveWritesWhatTheServerReadsAndLoadsItBack()
    {
        AllOn.Save(_database, null, () => _stopped);
        var rows = Rows();
        Assert.That(rows["bot_guilds_enabled"], Is.EqualTo("True"));
        Assert.That(rows["bot_guild_share"], Is.EqualTo("0.6"));
        Assert.That(rows["bot_guild_min_level"], Is.EqualTo("10"));
        Assert.That(rows["bot_guild_alliances"], Is.EqualTo("False"));
        Assert.That(rows["bot_personalities_enabled"], Is.EqualTo("True"));
        Assert.That(rows["xp_rate_by_level"], Is.EqualTo("1-19:3;20-34:5;35-50:12"));
        Assert.That(rows["xp_rate"], Is.EqualTo("1"), "the flat rate is not touched");
        var problems = new List<string>();
        Assert.That(SocialExpansionSettings.Load(_database, problems), Is.EqualTo(AllOn));
        Assert.That(problems, Is.Empty);
    }

    [Test] public void SaveOnlyWritesWhatChanged()
    {
        Exec("INSERT INTO ServerProperty VALUES ('guild', 'bot_guild_share', 'd', '', '0.655', '', 'bot_guild_share')");
        var loaded = SocialExpansionSettings.Load(_database, new List<string>());
        Assert.That(loaded.GuildSharePercent, Is.EqualTo(66));
        (loaded with { Personalities = true }).Save(_database, loaded, () => _stopped);
        var rows = Rows();
        Assert.That(rows["bot_guild_share"], Is.EqualTo("0.655"), "an untouched setting keeps its exact value");
        Assert.That(rows["bot_personalities_enabled"], Is.EqualTo("True"));
        Assert.That(rows.ContainsKey("bot_guilds_enabled"), Is.False);
    }

    [Test] public void UnreadableValuesAreReportedAndShownAsDefaults()
    {
        Exec("""
            INSERT INTO ServerProperty VALUES ('guild', 'bot_guilds_enabled', 'd', '', 'maybe', '', 'bot_guilds_enabled');
            INSERT INTO ServerProperty VALUES ('guild', 'bot_guild_share', 'd', '', '1.5', '', 'bot_guild_share');
            INSERT INTO ServerProperty VALUES ('rates', 'bot_xp_rate_by_level', 'd', '', '50-1:2', '', 'bot_xp_rate_by_level');
            """);
        var problems = new List<string>();
        var loaded = SocialExpansionSettings.Load(_database, problems);
        Assert.That(loaded.BotGuilds, Is.False);
        Assert.That(loaded.GuildSharePercent, Is.EqualTo(70));
        Assert.That(problems, Has.Count.EqualTo(2));
        Assert.That(loaded.BotXpByLevel, Is.EqualTo("50-1:2"), "an invalid range setting is kept so its error can be shown");
        Assert.That(loaded.Validate(), Does.Contain("ends before it starts"));
    }

    [Test] public void NothingIsWrittenWhileTheServerRunsOrWithInvalidRanges()
    {
        _stopped = false;
        Assert.Throws<InvalidOperationException>(() => AllOn.Save(_database, null, () => _stopped));
        _stopped = true;
        Assert.Throws<InvalidOperationException>(() => (AllOn with { PlayerXpByLevel = "1-19:3;10-20:2" }).Save(_database, null, () => _stopped));
        Assert.Throws<InvalidOperationException>(() => (AllOn with { BotXpByLevel = "1-50:0" }).Save(_database, null, () => _stopped));
        Assert.That(Rows().Keys, Is.EquivalentTo(new[] { "xp_rate" }));
    }

    /// <summary>The keys and defaults here must be the server's (ServerProperties.cs), or the tab would show the wrong state.</summary>
    [Test] public void KeysAndDefaultsMatchTheServer()
    {
        string? dir = TestContext.CurrentContext.TestDirectory;
        while (dir != null && !File.Exists(Path.Combine(dir, "source/server/GameServer/serverproperty/ServerProperties.cs")))
            dir = Path.GetDirectoryName(dir);
        if (dir == null) Assert.Ignore("Server source not found beside the tests.");
        string source = File.ReadAllText(Path.Combine(dir!, "source/server/GameServer/serverproperty/ServerProperties.cs"));
        var defaults = SocialExpansionSettings.Defaults.ToStoredValues();
        foreach (var (key, category, _) in typeof(SocialExpansionSettings)
                     .GetField("Settings", BindingFlags.Static | BindingFlags.NonPublic)!
                     .GetValue(null) as (string Key, string Category, string Description)[] ?? [])
        {
            var match = Regex.Match(source, $"\\[ServerProperty\\(\"(\\w+)\", \"{key}\", \"(?:[^\"\\\\]|\\\\.)*\", ([^)]*)\\)\\]");
            Assert.That(match.Success, Is.True, key + " is not a server setting");
            Assert.That(match.Groups[1].Value, Is.EqualTo(category), key + " category");
            string serverDefault = match.Groups[2].Value.Trim().Trim('"');
            string expected = serverDefault switch
            {
                "true" => "True",
                "false" => "False",
                _ when double.TryParse(serverDefault, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double d)
                    => d.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
                _ => serverDefault,
            };
            Assert.That(defaults[key], Is.EqualTo(expected), key + " default");
        }
    }

    [Test] public void TheTabFollowsTheServerStateAndDependencies()
    {
        var type = Assembly.Load("OfflineDAoC").GetType("OfflineDaoc.Launcher.SocialExpansionSettingsControl")!;
        using var panel = (Control)Activator.CreateInstance(type, _database, (Func<bool>)(() => _stopped))!;
        T Field<T>(string name) => (T)type.GetField(name, Hidden)!.GetValue(panel)!;
        void Call(string name) => type.GetMethod(name, Hidden | BindingFlags.Public)!.Invoke(panel, null);

        var guilds = Field<CheckBox>("_guilds");
        var claims = Field<CheckBox>("_guildClaims");
        var voices = Field<CheckBox>("_voices");
        var debates = Field<CheckBox>("_debates");
        var save = Field<Button>("_save");
        Assert.That(claims.Enabled, Is.False, "guild parts wait for bot guilds");
        Assert.That(debates.Enabled, Is.False, "debates wait for voices");
        Assert.That(save.Enabled, Is.False, "nothing to save yet");

        guilds.Checked = true;
        voices.Checked = true;
        Assert.That(claims.Enabled && debates.Enabled && save.Enabled, Is.True);

        var playerXp = type.GetField("_playerXp", Hidden)!.GetValue(panel)!;
        var mode = (ComboBox)playerXp.GetType().GetField("_mode", Hidden)!.GetValue(playerXp)!;
        var text = (TextBox)playerXp.GetType().GetField("_text", Hidden)!.GetValue(playerXp)!;
        mode.SelectedIndex = 2;
        text.Text = "1-19:3;15-30:2";
        Assert.That(save.Enabled, Is.False, "overlapping ranges can't be saved");
        mode.SelectedIndex = 1;
        Assert.That(text.Text, Is.EqualTo(SocialExpansionSettings.SuggestedPlayerXp));

        _stopped = false;
        Call("UpdateState");
        Assert.That(save.Enabled || guilds.Enabled || mode.Enabled, Is.False, "locked while the server runs");
        Call("SaveSettings");
        Assert.That(Rows().ContainsKey("bot_guilds_enabled"), Is.False);

        _stopped = true;
        Call("UpdateState");
        Call("SaveSettings");
        var rows = Rows();
        Assert.That(rows["bot_guilds_enabled"], Is.EqualTo("True"));
        Assert.That(rows["bot_voices_enabled"], Is.EqualTo("True"));
        Assert.That(rows["xp_rate_by_level"], Is.EqualTo(SocialExpansionSettings.SuggestedPlayerXp));
        Assert.That(type.GetProperty("HasUnsavedChanges")!.GetValue(panel), Is.False);

        Field<Button>("_allOff").PerformClick();
        Call("SaveSettings");
        rows = Rows();
        Assert.That(rows["bot_guilds_enabled"], Is.EqualTo("False"));
        Assert.That(rows["xp_rate_by_level"], Is.EqualTo(""));
    }

    /// <summary>
    /// Renders the real launcher (Options, Bot Goals Setting and Social Expansion tabs) and the tab in several
    /// states to PNG files in TestResults' work folder (ui-preview\), so the look can be checked against the
    /// other settings screens. CI uploads them as an artifact.
    /// </summary>
    [Test] public void RendersPreviewsBesideTheOtherSettingsTabs()
    {
        string folder = Path.Combine(TestContext.CurrentContext.WorkDirectory, "ui-preview");
        Directory.CreateDirectory(folder);
        var launcher = Assembly.Load("OfflineDAoC");

        using (var form = (Form)Activator.CreateInstance(launcher.GetType("OfflineDaoc.Launcher.MainForm")!)!)
        {
            form.ShowInTaskbar = false;
            form.StartPosition = FormStartPosition.Manual;
            form.Location = new Point(-20_000, -20_000);
            form.Show();
            Application.DoEvents();
            TabControl tabs = All(form).OfType<TabControl>().First(t => t.TabPages.Cast<TabPage>().Any(p => p.Text == "Social Expansion"));
            foreach (var (tab, file) in new[] { ("Options", "1-options.png"), ("Bot Goals Setting", "2-bot-goals.png"), ("Social Expansion", "3-social-expansion-in-launcher.png") })
            {
                tabs.SelectedTab = tabs.TabPages.Cast<TabPage>().First(p => p.Text == tab);
                Application.DoEvents();
                using var image = new Bitmap(form.Width, form.Height);
                form.DrawToBitmap(image, new Rectangle(Point.Empty, image.Size));
                image.Save(Path.Combine(folder, file));
            }
        }

        var type = launcher.GetType("OfflineDaoc.Launcher.SocialExpansionSettingsControl")!;
        void Render(string file, Action<Control> setup)
        {
            using var host = new Form { ShowInTaskbar = false, StartPosition = FormStartPosition.Manual, Location = new Point(-20_000, -20_000),
                ClientSize = new Size(1180, 1060), BackColor = Color.FromArgb(35, 31, 26) };
            var panel = (Control)Activator.CreateInstance(type, _database, (Func<bool>)(() => _stopped))!;
            host.Controls.Add(panel);
            host.Show();
            setup(panel);
            type.GetMethod("UpdateState")!.Invoke(panel, null);
            Application.DoEvents();
            using var image = new Bitmap(host.ClientSize.Width, host.ClientSize.Height);
            panel.DrawToBitmap(image, new Rectangle(Point.Empty, image.Size));
            image.Save(Path.Combine(folder, file));
        }
        T F<T>(Control panel, string name) => (T)type.GetField(name, Hidden)!.GetValue(panel)!;
        void Xp(Control panel, string row, int mode, string? text = null)
        {
            var xp = type.GetField(row, Hidden)!.GetValue(panel)!;
            ((ComboBox)xp.GetType().GetField("_mode", Hidden)!.GetValue(xp)!).SelectedIndex = mode;
            if (text != null) ((TextBox)xp.GetType().GetField("_text", Hidden)!.GetValue(xp)!).Text = text;
        }

        Render("4-tab-all-off.png", _ => { });
        Render("5-tab-editing.png", panel =>
        {
            F<CheckBox>(panel, "_guilds").Checked = true;
            F<CheckBox>(panel, "_voices").Checked = true;
            F<CheckBox>(panel, "_personalities").Checked = true;
            Xp(panel, "_playerXp", 1);
            Xp(panel, "_botXp", 2, "1-19:1.5;15-34:2.5");
        });
        AllOn.Save(_database, null, () => true);
        Render("6-tab-saved-on.png", _ => { });
        _stopped = false;
        Render("7-tab-server-running.png", _ => { });
        TestContext.Progress.WriteLine("UI previews: " + folder);
    }

    private static IEnumerable<Control> All(Control root)
    {
        foreach (Control child in root.Controls)
        {
            yield return child;
            foreach (Control nested in All(child)) yield return nested;
        }
    }
}
