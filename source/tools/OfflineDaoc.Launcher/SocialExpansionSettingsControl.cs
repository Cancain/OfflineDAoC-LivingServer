namespace OfflineDaoc.Launcher;

/// <summary>
/// The launcher's Social Expansion tab: switches for bot guilds, personalities, voices and debates, and the
/// XP-by-level-range rates, saved like the Options tab's settings (server stopped; used at the next start).
/// It replaces the set_bot_guilds.py, set_bot_social.py and set_xp_by_level.py helpers for players.
/// </summary>
internal sealed class SocialExpansionSettingsControl : UserControl
{
    private const int TextWidth = 820;
    private readonly string _database;
    private readonly Func<bool> _serverStopped;
    private readonly CheckBox _guilds = Switch("Bot guilds: bots form realm guilds, wear guild names, group with guildmates, and you can /ginvite them");
    private readonly NumericUpDown _share = new() { Minimum = 0, Maximum = 100, Width = 70, AccessibleName = "Share of bots in guilds" };
    private readonly NumericUpDown _minLevel = new() { Minimum = 1, Maximum = 50, Width = 70, AccessibleName = "Lowest guild level" };
    private readonly CheckBox _guildSocial = Switch("Guild chat, greetings, answers to your /gu, and recruiting in /faction", indent: true);
    private readonly CheckBox _guildRecruit = Switch("Bot officers invite you to their guild (a yes/no box; needs guild chat)", indent: true);
    private readonly CheckBox _guildClaims = Switch("Bot guilds claim the keeps their realm takes, and defend them first", indent: true);
    private readonly CheckBox _guildEconomy = Switch("Dues from real loot, merit points and guild buffs", indent: true);
    private readonly CheckBox _guildAlliances = Switch("Each realm's RvR and raiding guilds form an alliance", indent: true);
    private readonly CheckBox _personalities = Switch("Bot personalities: Leveler, Socialite, Daredevil, Explorer, Crafter or No-lifer (target a bot and type /personality)");
    private readonly CheckBox _voices = Switch("Bot voices: period chat lines, each bot in its own writing style");
    private readonly CheckBox _debates = Switch("/faction debates and long threads, every 30-45 minutes while you play (needs bot voices)", indent: true);
    private readonly XpRow _playerXp = new("YOUR CHARACTERS", SocialExpansionSettings.SuggestedPlayerXp, "Suggested: 3x / 5x / 12x");
    private readonly XpRow _botXp = new("AUTONOMOUS BOTS", SocialExpansionSettings.SuggestedBotXp, "Suggested: 1.5x / 2.5x / 6x");
    private readonly Label _status = new() { AutoSize = true, MaximumSize = new Size(TextWidth, 0), Margin = new Padding(3, 8, 3, 3) };
    private readonly Button _save = new() { Text = "Save settings", AutoSize = true };
    private readonly Button _undo = new() { Text = "Undo edits", AutoSize = true };
    private readonly Button _allOff = new() { Text = "Turn everything off", AutoSize = true };
    private readonly System.Windows.Forms.Timer _poll = new() { Interval = 2000 };
    private SocialExpansionSettings _saved = SocialExpansionSettings.Defaults;
    private bool _loading, _rewriteAll;   // _rewriteAll: the saved values couldn't all be read; Save writes every setting
    private string _notice = "";

    public bool HasUnsavedChanges => _rewriteAll || ReadValues() != _saved;

    public SocialExpansionSettingsControl(string database, Func<bool> serverStopped)
    {
        _database = database;
        _serverStopped = serverStopped;
        Dock = DockStyle.Fill;
        BackColor = DaocTheme.Panel;
        ForeColor = DaocTheme.Text;
        AutoScroll = true;
        var body = new FlowLayoutPanel
        {
            Dock = DockStyle.Top, AutoSize = true, FlowDirection = FlowDirection.TopDown,
            WrapContents = false, Padding = new Padding(16),
        };
        body.Controls.Add(new Label { Text = "Social Expansion", AutoSize = true,
            Font = new Font(Font.FontFamily, 15, FontStyle.Bold), ForeColor = DaocTheme.GoldLight });
        body.Controls.Add(Note("Bots that feel like 2003 players. Everything here starts off; with it all off the game plays exactly " +
            "like the normal release. Changes apply on the next server start. Only autonomous gamebots change: your " +
            "/spawn companions and other players' characters are not affected.", 15));

        body.Controls.Add(Heading("BOT GUILDS"));
        body.Controls.Add(_guilds);
        var guildNumbers = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(24, 2, 3, 4) };
        guildNumbers.Controls.Add(Inline("Bots in guilds:"));
        guildNumbers.Controls.Add(_share);
        guildNumbers.Controls.Add(Inline("%     Lowest level that joins:"));
        guildNumbers.Controls.Add(_minLevel);
        body.Controls.Add(guildNumbers);
        body.Controls.AddRange([_guildSocial, _guildRecruit, _guildClaims, _guildEconomy, _guildAlliances]);

        body.Controls.Add(Heading("PERSONALITIES AND VOICES"));
        body.Controls.AddRange([_personalities, _voices, _debates]);

        body.Controls.Add(Heading("XP BY LEVEL RANGE"));
        body.Controls.Add(Note("Inside these level ranges the rate replaces the flat XP rate on the Options tab; other levels " +
            "keep it. The suggested rates keep levels 1-34 worth playing and shorten the 35-50 grind. Custom ranges look " +
            "like 1-19:3;20-34:5;35-50:12 (levels 1-50, rates above 0).", 6));
        body.Controls.Add(_playerXp.Panel);
        body.Controls.Add(_botXp.Panel);

        var buttons = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(0, 16, 0, 6) };
        buttons.Controls.AddRange([_save, _undo, _allOff]);
        body.Controls.Add(buttons);
        body.Controls.Add(_status);
        Controls.Add(body);

        foreach (var box in new[] { _guilds, _guildSocial, _guildRecruit, _guildClaims, _guildEconomy, _guildAlliances, _personalities, _voices, _debates })
            box.CheckedChanged += (_, _) => Edited();
        _share.ValueChanged += (_, _) => Edited();
        _minLevel.ValueChanged += (_, _) => Edited();
        _playerXp.Changed += Edited;
        _botXp.Changed += Edited;
        _save.Click += (_, _) => SaveSettings();
        _undo.Click += (_, _) => LoadSettings();
        _allOff.Click += (_, _) =>
        {
            SetValues(SocialExpansionSettings.Defaults);
            _notice = "Everything is switched off here. Click Save settings to apply.";
            UpdateState();
        };
        LoadSettings();
        _poll.Tick += (_, _) => UpdateState();
        _poll.Start();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _poll.Dispose();
        base.Dispose(disposing);
    }

    private void Edited()
    {
        if (_loading) return;
        _notice = "";
        UpdateState();
    }

    private SocialExpansionSettings ReadValues() => new()
    {
        BotGuilds = _guilds.Checked,
        GuildSharePercent = (int)_share.Value,
        GuildMinLevel = (int)_minLevel.Value,
        GuildSocial = _guildSocial.Checked,
        GuildRecruitPlayer = _guildRecruit.Checked,
        GuildClaims = _guildClaims.Checked,
        GuildEconomy = _guildEconomy.Checked,
        GuildAlliances = _guildAlliances.Checked,
        Personalities = _personalities.Checked,
        Voices = _voices.Checked,
        Debates = _debates.Checked,
        PlayerXpByLevel = _playerXp.Value,
        BotXpByLevel = _botXp.Value,
    };

    private void SetValues(SocialExpansionSettings settings)
    {
        _loading = true;
        _guilds.Checked = settings.BotGuilds;
        _share.Value = Math.Clamp(settings.GuildSharePercent, 0, 100);
        _minLevel.Value = Math.Clamp(settings.GuildMinLevel, 1, 50);
        _guildSocial.Checked = settings.GuildSocial;
        _guildRecruit.Checked = settings.GuildRecruitPlayer;
        _guildClaims.Checked = settings.GuildClaims;
        _guildEconomy.Checked = settings.GuildEconomy;
        _guildAlliances.Checked = settings.GuildAlliances;
        _personalities.Checked = settings.Personalities;
        _voices.Checked = settings.Voices;
        _debates.Checked = settings.Debates;
        _playerXp.Value = settings.PlayerXpByLevel;
        _botXp.Value = settings.BotXpByLevel;
        _loading = false;
    }

    private void LoadSettings()
    {
        var problems = new List<string>();
        try
        {
            _saved = SocialExpansionSettings.Load(_database, problems);
            _rewriteAll = problems.Count > 0;
            _notice = problems.Count == 0 ? "" : string.Join(" ", problems) + " Save to repair.";
            SetValues(_saved);
        }
        catch (Exception ex)
        {
            _rewriteAll = true;
            _saved = SocialExpansionSettings.Defaults;
            SetValues(_saved);
            _notice = "Cannot read the saved settings: " + ex.Message;
        }
        UpdateState();
    }

    private void SaveSettings()
    {
        try
        {
            var values = ReadValues();
            values.Save(_database, _rewriteAll ? null : _saved, _serverStopped);
            _saved = values;
            _rewriteAll = false;
            _notice = "Saved. These settings apply on the next server start.";
        }
        catch (Exception ex) { _notice = "Not saved: " + ex.Message; }
        UpdateState();
    }

    public void UpdateState()
    {
        bool stopped = _serverStopped();
        var values = ReadValues();
        string? invalid = values.Validate();
        _guilds.Enabled = _share.Enabled = _minLevel.Enabled = stopped;
        _guildSocial.Enabled = _guildClaims.Enabled = _guildEconomy.Enabled = _guildAlliances.Enabled = stopped && values.BotGuilds;
        _guildRecruit.Enabled = stopped && values.BotGuilds && values.GuildSocial;
        _personalities.Enabled = _voices.Enabled = stopped;
        _debates.Enabled = stopped && values.Voices;
        _playerXp.SetEnabled(stopped);
        _botXp.SetEnabled(stopped);
        _playerXp.ShowError(SocialExpansionSettings.XpError("Not valid", values.PlayerXpByLevel));
        _botXp.ShowError(SocialExpansionSettings.XpError("Not valid", values.BotXpByLevel));
        bool changed = HasUnsavedChanges;
        _save.Enabled = stopped && invalid is null && changed;
        _undo.Enabled = stopped && changed;
        _allOff.Enabled = stopped && values != SocialExpansionSettings.Defaults;
        if (!stopped)
        {
            _status.Text = "The server is running. Stop it to change these settings." + (_notice == "" ? "" : " " + _notice);
            _status.ForeColor = DaocTheme.Muted;
        }
        else if (invalid is not null)
        {
            _status.Text = invalid;
            _status.ForeColor = DaocTheme.Danger;
        }
        else if (_notice != "")
        {
            _status.Text = _notice;
            _status.ForeColor = _notice.StartsWith("Not saved", StringComparison.Ordinal) || _notice.StartsWith("Cannot", StringComparison.Ordinal)
                ? DaocTheme.Danger : DaocTheme.Success;
        }
        else
        {
            _status.Text = changed ? "Unsaved edits. Click Save settings to apply them on the next server start." : Summary(_saved);
            _status.ForeColor = changed ? DaocTheme.GoldLight : DaocTheme.Muted;
        }
    }

    private static string Summary(SocialExpansionSettings s)
    {
        var on = new List<string>();
        if (s.BotGuilds) on.Add("bot guilds");
        if (s.Personalities) on.Add("personalities");
        if (s.Voices) on.Add(s.Debates ? "voices and debates" : "voices");
        if (s.PlayerXpByLevel != "" || s.BotXpByLevel != "") on.Add("XP by level");
        return on.Count == 0 ? "Saved: everything off (the normal game)." : "Saved and on at the next start: " + string.Join(", ", on) + ".";
    }

    private static CheckBox Switch(string text, bool indent = false) => new()
    {
        Text = text, AutoSize = true, MaximumSize = new Size(TextWidth, 0),
        Margin = new Padding(indent ? 24 : 3, 4, 3, 4), ForeColor = DaocTheme.Parchment,
        Font = new Font("Georgia", indent ? 9f : 9.5f, indent ? FontStyle.Regular : FontStyle.Bold),
    };

    private static Label Heading(string text) => new()
    {
        Text = text, AutoSize = true, Margin = new Padding(3, 14, 3, 4),
        Font = new Font("Georgia", 11f, FontStyle.Bold), ForeColor = DaocTheme.Gold,
    };

    private static Label Note(string text, int bottom) => new()
    {
        Text = text, AutoSize = true, MaximumSize = new Size(TextWidth, 0),
        Margin = new Padding(3, 8, 3, bottom), ForeColor = DaocTheme.Muted,
    };

    private static Label Inline(string text) => new()
    {
        Text = text, AutoSize = true, Margin = new Padding(3, 6, 3, 3), ForeColor = DaocTheme.Parchment,
    };

    /// <summary>One XP-by-level row: Off, the suggested ranges, or custom ranges typed in.</summary>
    private sealed class XpRow
    {
        private const int Off = 0, Suggested = 1, Custom = 2;
        private readonly string _suggested;
        private readonly ComboBox _mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 210 };
        private readonly TextBox _text = new() { Width = 260 };
        private readonly Label _error = new() { AutoSize = true, MaximumSize = new Size(TextWidth, 0), ForeColor = DaocTheme.Danger, Margin = new Padding(24, 0, 3, 4) };
        private bool _setting;
        public event Action? Changed;
        public FlowLayoutPanel Panel { get; }

        public XpRow(string label, string suggested, string suggestedLabel)
        {
            _suggested = suggested;
            _mode.Items.AddRange(["Off (flat rate)", suggestedLabel, "Custom ranges"]);
            _mode.AccessibleName = label + " XP by level";
            _text.AccessibleName = label + " XP ranges";
            var row = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(3, 2, 3, 0) };
            row.Controls.Add(new Label { Text = label, AutoSize = false, Width = 150, Height = 24, TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = DaocTheme.Parchment, Font = new Font("Georgia", 9f, FontStyle.Bold) });
            row.Controls.Add(_mode);
            row.Controls.Add(_text);
            Panel = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Margin = new Padding(0) };
            Panel.Controls.Add(row);
            Panel.Controls.Add(_error);
            _mode.SelectedIndexChanged += (_, _) =>
            {
                if (_setting) return;
                if (_mode.SelectedIndex == Off) _text.Text = "";
                else if (_mode.SelectedIndex == Suggested) _text.Text = _suggested;
                else if (_text.Text.Trim() == "") _text.Text = _suggested;
                _text.ReadOnly = _mode.SelectedIndex != Custom;
                Changed?.Invoke();
            };
            _text.TextChanged += (_, _) => { if (!_setting) Changed?.Invoke(); };
            Value = "";
        }

        public string Value
        {
            get => _mode.SelectedIndex == Off ? "" : _text.Text.Trim();
            set
            {
                _setting = true;
                string text = value.Trim();
                _mode.SelectedIndex = text == "" ? Off : Normalize(text) == Normalize(_suggested) ? Suggested : Custom;
                _text.Text = text;
                _text.ReadOnly = _mode.SelectedIndex != Custom;
                _setting = false;
            }
        }

        public void SetEnabled(bool enabled)
        {
            _mode.Enabled = enabled;
            _text.Enabled = enabled && _mode.SelectedIndex != Off;
        }

        public void ShowError(string? error)
        {
            _error.Text = error ?? "";
            _error.Visible = error is not null;
        }

        private static string Normalize(string spec) => string.Concat(spec.Where(c => !char.IsWhiteSpace(c))).TrimEnd(';');
    }
}
