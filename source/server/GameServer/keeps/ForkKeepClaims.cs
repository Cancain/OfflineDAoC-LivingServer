using System.Collections.Generic;
using System.Linq;
using DOL.GS.PacketHandler;
using DOL.GS.ServerProperties;

namespace DOL.GS.Keeps;

/// <summary>
/// Fork: guild claims of battleground keeps. Kept out of upstream's keep classes, which only call in here, so they stay
/// easy to merge. Every switch is off by default, and upstream's allow_bg_claim stays off: it would also open the
/// portal keeps, since it only checks BaseLevel != 50.
/// - fork_bg_claim: a keep in a region of the Battleground table may be claimed (never a portal or relic keep), and a
///   claimed battleground keep keeps its level: no starting_keep_claim_level on the claim, no level change over time, and
///   a release leaves it at that level instead of starting_keep_level. The lord's "Claim Keep" follows the limits below.
/// - fork_claim_counts_group_bots: the companions and autonomous bots in the claiming player's group count towards
///   claim_num when they are alive and in the keep's area, as the players do. The bot guilds' own claims are not changed.
/// - fork_bot_guilds_claim_bg: bot guilds may claim battleground keeps too (needs fork_bg_claim).
/// - fork_bg_claim_limit: with fork_bg_claim on, a guild's battleground claims count only against this limit and its
///   frontier claims only against guilds_claim_limit, for players and bot guilds alike. Off, upstream counts every claim.
/// tools/fork-build/set-bg-claim.ps1 switches them in a stopped server's database.
/// </summary>
public static class ForkKeepClaims
{
    [ServerProperty("fork", "fork_bg_claim", "Fork: guilds may claim battleground keeps (never portal or relic keeps); a claimed battleground keep keeps its level.", false)]
    public static bool FORK_BG_CLAIM;

    [ServerProperty("fork", "fork_claim_counts_group_bots", "Fork: the claiming player's group companions and autonomous bots in the keep's area count towards claim_num.", false)]
    public static bool FORK_CLAIM_COUNTS_GROUP_BOTS;

    [ServerProperty("fork", "fork_bot_guilds_claim_bg", "Fork: bot guilds may claim battleground keeps (needs fork_bg_claim).", false)]
    public static bool FORK_BOT_GUILDS_CLAIM_BG;

    [ServerProperty("fork", "fork_bg_claim_limit", "Fork: how many battleground keeps a guild may claim when fork_bg_claim is on (frontier keeps count against guilds_claim_limit).", 1)]
    public static int FORK_BG_CLAIM_LIMIT;

    #region Pure rules (tested)

    /// <summary>The claims that count against a keep's limit: with the fork switch on, only those of the same kind
    /// (battleground or frontier); off, all of them, as upstream.</summary>
    public static int ClaimCount(bool enabled, bool battleground, IEnumerable<bool> claimedAreBattleground)
    {
        bool[] claimed = (claimedAreBattleground ?? []).ToArray();
        return enabled ? claimed.Count(kind => kind == battleground) : claimed.Length;
    }

    /// <summary>Why a guild may not claim one more keep under this limit, in upstream's words; null when it may.</summary>
    public static string ClaimLimitRefusal(bool battleground, int limit, int claimed)
    {
        if (limit <= 0)
            return battleground ? "Battleground keep claiming is disabled!" : "Keep claiming is disabled!";
        if (claimed < limit)
            return null;
        if (limit == 1)
            return battleground ? "Your guild already owns a battleground keep." : "Your guild already owns a keep.";
        return $"Your guild already owns the limit of {(battleground ? "battleground keeps" : "keeps")} ({limit})";
    }

    public static bool IsClaimableBattlegroundKeep(bool enabled, bool battlegroundRegion, bool portalKeep, bool relicKeep) =>
        enabled && battlegroundRegion && !portalKeep && !relicKeep;

    public static bool HoldsLevel(bool enabled, bool claimed, bool battlegroundKeep) =>
        enabled && claimed && battlegroundKeep;

    public static byte ReleaseLevel(bool enabled, bool battlegroundKeep, byte currentLevel, byte startingLevel) =>
        enabled && battlegroundKeep ? currentLevel : startingLevel;

    public readonly record struct BotPresence(bool Alive, bool InArea);

    /// <summary>The players present plus, when switched on, the group's bots that are alive and in the keep's area.</summary>
    public static int CountPresent(bool enabled, int playersPresent, IEnumerable<BotPresence> bots) =>
        enabled ? playersPresent + (bots ?? []).Count(bot => bot.Alive && bot.InArea) : playersPresent;

    #endregion

    #region Runtime

    public static bool IsBattlegroundRegion(AbstractGameKeep keep) =>
        keep != null && GameServer.KeepManager?.GetBattleground(keep.Region) != null;

    /// <summary>A keep of a battleground region that is no portal keep: claimed ones keep their level and have their own limit.</summary>
    public static bool IsBattlegroundKeep(AbstractGameKeep keep) =>
        IsBattlegroundRegion(keep) && !keep.IsPortalKeep;

    /// <summary>The claim limit for this keep: fork_bg_claim_limit for a battleground keep with fork_bg_claim on, else
    /// guilds_claim_limit (AutonomousBotGuildKeeps.TryClaim).</summary>
    public static int ClaimLimit(AbstractGameKeep keep) =>
        FORK_BG_CLAIM && IsBattlegroundKeep(keep) ? FORK_BG_CLAIM_LIMIT : Properties.GUILDS_CLAIM_LIMIT;

    /// <summary>The guild's claims that count against this keep's limit (AutonomousBotGuildKeeps.TryClaim).</summary>
    public static int ClaimCount(AbstractGameKeep keep, Guild guild) =>
        guild == null ? 0 : ClaimCount(FORK_BG_CLAIM, IsBattlegroundKeep(keep), guild.ClaimedKeeps.ToArray().Select(IsBattlegroundKeep));

    /// <summary>The guild may claim one more keep of this kind (PlayerMgr.IsAllowedToInteract: the lord's "Claim Keep";
    /// upstream refused a guild that owned any keep at all).</summary>
    public static bool WithinClaimLimit(AbstractGameKeep keep, Guild guild) =>
        ClaimLimitRefusal(IsBattlegroundKeep(keep), ClaimLimit(keep), ClaimCount(keep, guild)) == null;

    /// <summary>AbstractGameKeep.Release: the level a released keep goes to. With fork_bg_claim on a battleground keep
    /// keeps its own (the claim never changed it, so it is the level from before the claim; a capture has already set
    /// starting_keep_level); otherwise starting_keep_level, as upstream.</summary>
    public static byte ReleaseLevel(AbstractGameKeep keep, byte startingLevel) =>
        ReleaseLevel(FORK_BG_CLAIM, IsBattlegroundKeep(keep), keep.Level, startingLevel);

    /// <summary>
    /// AbstractGameKeep.CheckForClaim: with fork_bg_claim on, the claim limit is checked here (battleground and frontier
    /// keeps each against their own limit) instead of upstream's switch, and a refusal is told to the player. Off: false,
    /// and upstream's switch decides, as before.
    /// </summary>
    public static bool HandlesClaimLimit(AbstractGameKeep keep, GamePlayer player, out bool withinLimit)
    {
        withinLimit = true;
        if (!FORK_BG_CLAIM)
            return false;

        string refusal = ClaimLimitRefusal(IsBattlegroundKeep(keep), ClaimLimit(keep), ClaimCount(keep, player.Guild));
        if (refusal != null)
        {
            player.Out.SendMessage(refusal, eChatType.CT_System, eChatLoc.CL_SystemWindow);
            withinLimit = false;
        }

        return true;
    }

    /// <summary>AbstractGameKeep.CheckForClaim: a battleground keep a player may claim.</summary>
    public static bool IsClaimableBattlegroundKeep(AbstractGameKeep keep) =>
        IsClaimableBattlegroundKeep(FORK_BG_CLAIM, IsBattlegroundRegion(keep), keep?.IsPortalKeep ?? true, keep is RelicGameKeep);

    /// <summary>AutonomousBotGuildKeeps.TryClaim: a battleground keep a bot guild may claim.</summary>
    public static bool BotGuildsMayClaim(AbstractGameKeep keep) =>
        FORK_BOT_GUILDS_CLAIM_BG && IsClaimableBattlegroundKeep(keep);

    /// <summary>AbstractGameKeep.ChangeLevel and StartChangeLevel: a claimed battleground keep keeps its level.</summary>
    public static bool HoldsLevel(AbstractGameKeep keep) =>
        HoldsLevel(FORK_BG_CLAIM, keep?.Guild != null, IsBattlegroundKeep(keep));

    /// <summary>AbstractGameKeep.CheckForClaim: the players present (counted upstream) plus the group's bots.</summary>
    public static int CountPresent(Group group, IArea area, int playersPresent)
    {
        if (!FORK_CLAIM_COUNTS_GROUP_BOTS || group == null || area == null)
            return playersPresent;

        return CountPresent(true, playersPresent, group.GetMembersInTheGroup()
            .OfType<GameBot>()
            .Select(bot => new BotPresence(bot.IsAlive && bot.ObjectState == GameObject.eObjectState.Active, bot.CurrentAreas.Contains(area))));
    }

    #endregion
}
