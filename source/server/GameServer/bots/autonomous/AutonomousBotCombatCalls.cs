using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using DOL.AI.Brain;
using DOL.GS.Spells;
using DOL.Logging;
using VC = DOL.GS.AutonomousBotVoiceCorpus;

namespace DOL.GS;

/// <summary>
/// Combat calls in the real player's group (the talking update). Gamebots in a player's group went silent the moment a fight
/// started, so a group of bots fought like pets. Now they call what is really happening, in /group and briefly: the pull
/// ("inc"), an add ("add, add"), their own low health or power ("need a heal", "oom"), a mez, root, stun, taunt, group heal or
/// rez they are casting right now, a wipe ("run!") and the end of the fight ("gj", "med up"). Every call comes from the
/// group's or the bot's real state; nothing is said on a guess. The decisions are pure (unit-tested); Observe reads the game.
/// </summary>
public static class AutonomousBotCombatCalls
{
    private static readonly Logger Log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);

    /// <summary>How often a bot looks at the fight.</summary>
    public const int CheckMs = 1_000;
    /// <summary>At most one call in the group this often (a wipe call excepted).</summary>
    public const int GroupGapMs = 3_500;
    /// <summary>At most one call by a bot this often.</summary>
    public const int BotGapMs = 8_000;
    public const int AddGapMs = 15_000;
    public const int LowHpGapMs = 45_000;
    public const int OomGapMs = 60_000;
    public const int CastGapMs = 20_000;

    public const int LowHpPercent = 30;
    public const int LowHpResetPercent = 50;
    public const int OomPercent = 15;
    public const int OomResetPercent = 40;

    /// <summary>The group's fight as one bot sees it this second.</summary>
    public sealed record GroupView(bool Fighting, int Enemies, int Members, int Alive, bool Worn);

    public sealed class GroupState
    {
        public bool WasFighting;
        public int MaxEnemies;
        public int DeadAtStart;
        public bool WipeCalled;
        public long LastAdd = long.MinValue / 2;
        public long LastCall = long.MinValue / 2;
        public long LastObserved = long.MinValue / 2;
    }

    public sealed class BotState
    {
        public long NextCheck;
        public bool WasLow;
        public bool WasOom;
        public long LastLow = long.MinValue / 2;
        public long LastOom = long.MinValue / 2;
        public long LastCall = long.MinValue / 2;
        public readonly Dictionary<string, long> LastCast = new(StringComparer.Ordinal);
        public object LastHandler;
    }

    /// <summary>
    /// What the group's fight calls for now, or null: "pull" when it starts, "add" when more enemies join than it had, "wipe"
    /// when half the group has died in it, "kill" or "rest" when it ends (rest more likely when the group is worn). Updates the
    /// state; the caller checks the group gap.
    /// </summary>
    public static string GroupEvent(GroupState state, GroupView view, long now, Random random)
    {
        if (!state.WasFighting && view.Fighting)
        {
            state.WasFighting = true;
            state.MaxEnemies = view.Enemies;
            state.DeadAtStart = view.Members - view.Alive;
            state.WipeCalled = false;
            return view.Enemies >= 1 && random.NextDouble() < 0.35 ? "pull" : null;
        }
        if (state.WasFighting && view.Fighting)
        {
            int dead = view.Members - view.Alive;
            if (!state.WipeCalled && view.Members >= 3 && view.Alive * 2 <= view.Members && dead > state.DeadAtStart)
            {
                state.WipeCalled = true;
                return random.NextDouble() < 0.8 ? "wipe" : null;
            }
            if (view.Enemies > state.MaxEnemies && view.Enemies >= 2)
            {
                state.MaxEnemies = view.Enemies;
                if (now - state.LastAdd < AddGapMs)
                    return null;
                state.LastAdd = now;
                return random.NextDouble() < 0.75 ? "add" : null;
            }
            return null;
        }
        if (state.WasFighting && !view.Fighting)
        {
            state.WasFighting = false;
            if (state.WipeCalled || view.Alive <= 0)
                return null;
            double roll = random.NextDouble();
            if (view.Worn)
                return roll < 0.45 ? "rest" : roll < 0.6 ? "kill" : null;
            return roll < 0.3 ? "kill" : roll < 0.4 ? "rest" : null;
        }
        return null;
    }

    /// <summary>
    /// What a bot's own state calls for, or null: "low_hp" as its health drops under 30% in a fight, "oom" as a caster's or
    /// healer's power drops under 15%. Each fires once on the way down and again only after the bot has recovered.
    /// </summary>
    public static string SelfEvent(BotState state, bool inCombat, int healthPercent, int manaPercent, bool usesPower, long now, Random random)
    {
        if (healthPercent >= LowHpResetPercent)
            state.WasLow = false;
        if (manaPercent >= OomResetPercent)
            state.WasOom = false;
        if (inCombat && healthPercent > 0 && healthPercent < LowHpPercent && !state.WasLow)
        {
            state.WasLow = true;
            if (now - state.LastLow >= LowHpGapMs && random.NextDouble() < 0.6)
            {
                state.LastLow = now;
                return "low_hp";
            }
        }
        if (usesPower && manaPercent < OomPercent && !state.WasOom)
        {
            state.WasOom = true;
            if (now - state.LastOom >= OomGapMs && random.NextDouble() < 0.7)
            {
                state.LastOom = now;
                return "oom";
            }
        }
        return null;
    }

    /// <summary>The call a spell being cast fits ("mez", "root", "stun", "heal_big", "rez", "taunt"), or null.</summary>
    public static string CastTopic(eSpellType type, eSpellTarget target, double value, int enemies) => type switch
    {
        // The mez lines say "the add": only with more than one enemy.
        eSpellType.Mesmerize when enemies >= 2 => "mez",
        eSpellType.Stun when target is eSpellTarget.ENEMY or eSpellTarget.AREA or eSpellTarget.CONE => "stun",
        eSpellType.SpeedDecrease or eSpellType.UnbreakableSpeedDecrease when value >= 99 => "root",
        eSpellType.Heal when target == eSpellTarget.GROUP => "heal_big",
        eSpellType.Resurrect => "rez",
        eSpellType.Taunt => "taunt",
        _ => null
    };

    /// <summary>How likely a bot calls the spell it casts (a rez nearly always, a stun now and then).</summary>
    public static double CastChance(string topic) => topic switch
    {
        "rez" => 0.7,
        "mez" => 0.5,
        "root" => 0.4,
        "heal_big" => 0.35,
        "stun" => 0.3,
        "taunt" => 0.25,
        _ => 0
    };

    /// <summary>True when a call may go out now (the group and bot gaps), and books it.</summary>
    public static bool Gate(GroupState group, BotState bot, string topic, long now)
    {
        if (topic != "wipe" && now - group.LastCall < GroupGapMs)
            return false;
        if (now - bot.LastCall < BotGapMs)
            return false;
        group.LastCall = now;
        bot.LastCall = now;
        return true;
    }

    private static readonly ConditionalWeakTable<Group, GroupState> Groups = new();
    private static readonly ConditionalWeakTable<GameBot, BotState> Bots = new();

    /// <summary>From the bot's think: a bot in the real player's group looks at the fight once a second.</summary>
    public static void Observe(GameBot bot)
    {
        if (!AutonomousBotVoices.Enabled || bot?.Group == null || !bot.IsAutonomousWorldBot || bot.IsTemporaryGroupHelper ||
            bot.DatabaseID <= 0)
            return;
        long now = GameLoop.GameLoopTime;
        BotState self = Bots.GetValue(bot, _ => new BotState());
        if (now < self.NextCheck)
            return;
        self.NextCheck = now + CheckMs;
        try
        {
            Group group = bot.Group;
            if (!AutonomousLivingServer.GroupHasPlayer(group))
                return;
            GroupState state = Groups.GetValue(group, _ => new GroupState());
            GameLiving[] members = group.GetMembersInTheGroup().ToArray();
            int enemies = CountEnemies(members);
            lock (state)
            {
                if (now - state.LastObserved >= CheckMs - 100)
                {
                    state.LastObserved = now;
                    var view = new GroupView(members.Any(m => m.IsAlive && m.InCombat), enemies, members.Length,
                        members.Count(m => m.IsAlive), members.Any(m => m.IsAlive && (m.HealthPercent < 50 || m.MaxMana > 0 && m.ManaPercent < 40)));
                    string topic = GroupEvent(state, view, now, Random.Shared);
                    if (topic != null)
                        CallForGroup(group, members, state, topic, now);
                }
            }
            if (!bot.IsAlive)
                return;
            string own = SelfEvent(self, bot.InCombat, bot.HealthPercent, bot.ManaPercent, UsesPower(bot), now, Random.Shared);
            if (own == null && bot.IsCasting && bot.CurrentSpellHandler is ISpellHandler handler && !ReferenceEquals(handler, self.LastHandler))
            {
                self.LastHandler = handler;
                Spell spell = handler.Spell;
                string cast = spell == null ? null : CastTopic(spell.SpellType, spell.Target, spell.Value, enemies);
                if (cast != null && (!self.LastCast.TryGetValue(cast, out long last) || now - last >= CastGapMs) &&
                    Random.Shared.NextDouble() < CastChance(cast))
                {
                    self.LastCast[cast] = now;
                    own = cast;
                }
            }
            if (own != null)
                lock (state)
                    if (Gate(state, self, own, now))
                        Say(bot, own);
        }
        catch (Exception exception)
        {
            Log.Warn($"Bot voices: combat call for {bot.Name} failed", exception);
        }
    }

    private static void CallForGroup(Group group, GameLiving[] members, GroupState state, string topic, long now)
    {
        GameBot[] bots = members.OfType<GameBot>()
            .Where(b => b.IsAlive && b.IsAutonomousWorldBot && !b.IsTemporaryGroupHelper && b.DatabaseID > 0)
            .OrderBy(_ => Random.Shared.Next()).ToArray();
        if (bots.Length == 0)
            return;
        // The pull and adds are seen first by whoever is in the fight, a tank before anyone.
        IEnumerable<GameBot> order = topic is "pull" or "add"
            ? bots.OrderByDescending(b => b.InCombat).ThenByDescending(IsTank)
            : bots;
        foreach (GameBot speaker in order)
        {
            BotState self = Bots.GetValue(speaker, _ => new BotState());
            if (!Gate(state, self, topic, now))
                return;
            if (Say(speaker, topic))
                return;
            // Nothing to say for this bot (its role has no line): let the next one try.
            state.LastCall = long.MinValue / 2;
            self.LastCall = long.MinValue / 2;
        }
    }

    private static bool Say(GameBot bot, string topic)
    {
        if (!AutonomousBotVoices.TryLine(bot, "combat", out VC.Picked picked, topic: topic, relax: true))
            return false;
        AutonomousBotGroupChatter.Send(bot, picked.Text);
        return true;
    }

    /// <summary>The distinct live enemies fighting anyone in the group (monsters and enemy players, not pets of the group).</summary>
    private static int CountEnemies(GameLiving[] members)
    {
        var seen = new HashSet<GameLiving>();
        foreach (GameLiving member in members)
        {
            if (member?.attackComponent?.AttackerTracker == null)
                continue;
            foreach (GameLiving attacker in member.attackComponent.AttackerTracker.Attackers)
                if (attacker != null && attacker.IsAlive && !members.Contains(attacker) &&
                    !(attacker is GameNPC npc && npc.Brain is IControlledBrain controlled && members.Contains(controlled.Owner)))
                    seen.Add(attacker);
        }
        return seen.Count;
    }

    private static bool UsesPower(GameBot bot)
    {
        if (bot.CharacterClass == null || bot.MaxMana <= 0)
            return false;
        var cls = (eCharacterClass)bot.CharacterClass.ID;
        return AutonomousBotVoices.IsCasterClass(cls) || BotPartyRoles.IsHealingClass(cls);
    }

    private static bool IsTank(GameBot bot) =>
        bot.CharacterClass != null && BotPartyRoles.For((eCharacterClass)bot.CharacterClass.ID) == BotPartyRole.Tank;
}
