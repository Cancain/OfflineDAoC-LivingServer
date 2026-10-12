# Bot guilds: design and status

Goal: autonomous gamebots belong to guilds the way 2003 players did. Each realm has a spread of
bot guilds, a few big and many small, each with a purpose (its **charter**). Bots carry the guild
name over their heads and show up in the guild window. Later phases add guild chat, grouping with
guildmates, guild keeps, the bank and guild buffs. You can invite a bot into your own guild.

This affects only **autonomous gamebots**. Companion bots (`/spawn`, `/raid`) and real players
keep today's behavior.

## 1. What other forks have (checked 2026-10-12)

| Source | Bot guilds? | Use for us |
|---|---|---|
| Original (`shadowofze/OfflineDAoC`, `1cabc77`) | No. `GameBot.Guild` exists, but nothing assigns it. | Base |
| `stefanrows/OfflineDAoC` | **Yes, extensive.** "Camlann crews": up to 15 guilds with **no realm**, mixing all three realms, because that fork replaced three-realm RvR with free-for-all PvP. Includes bot members in the core `Guild` class, bots in the guild window, `/ginvite` on bots, guild chat both ways, charters, guild cohesion, grudges, keep defense and guild armies. | **Ported:** the core bot-member plumbing in `Guild`, adapted (credited in the code). **Ideas only:** charters, cohesion, grudges, keep defense. Its formation code assumes realmless guilds and isn't reused. |
| `lometur/HearthDAoC` | No (4 small guild-related lines, the same as the original) | — |
| Other identified forks (`scaleysandwich`, `BeezKneezItem9`, `BlakeFL`, `ThatFontGuy`, `catastrophic-impact`) | Not in their stated scope; small forks | — |

**Unchecked:** 4 of the original's 13 forks can't be identified from here, because the GitHub fork
list is blocked.

**Outside DAoC:** WoW server projects such as AzerothCore's playerbots module are known for bot
guilds. That is an idea source only; it wasn't examined in detail.

## 2. How guilds work in the base (verified in code)

**For players:**
- **Membership** works through `GamePlayer` and character rows (`DbCoreCharacter.GuildID`): ranks
  0–9, guild chat, the bank and dues, guild buffs (`guild_buff_xp` 5%, crafting 5%, RP 2%), keep
  claims (`AbstractGameKeep.Claim(GamePlayer)`), alliances and guild houses.
- **Bots fit none of this today.** They aren't characters (they're `offline_world_bots` rows),
  `Guild.AddPlayer` takes a `GamePlayer`, and `/ginvite` only targets players.

**Already wired for bots:**
- `GameBot.Guild`.
- The bot XP award applies the guild XP buff when the bot's guild has it.
- A bot NPC shows its `GuildName` over its head, and setting it re-sends the bot to nearby clients.
- Enemy viewers see a realm-rank title instead (`AutonomousNameMask`).

**Shipped guilds:** the release ships only the three starting guilds (Clan Cotswold, Mularn
Protectors, Tir na Nog Adventurers).

## 3. Design

### 3.1 Charters (what a guild is for)

| Charter | Membership leans toward | Later behavior |
|---|---|---|
| Leveling | levels 5–40 | groups with guildmates at camps |
| Social | any level | chatty guild chat, invites, events |
| RvR | level 35+ | musters, frontier raids, keep claims |
| Raiding | level 40+ | dungeon and dragon raids |
| Crafting | any level, crafters | trade talk, orders, bank |

### 3.2 Formation (per realm, deterministic, gradual)

- **Who's eligible:** non-retired bots of level 5 or more (`bot_guild_min_level`) that aren't in a
  player's guild.
- **How many join:** about 70% of eligible bots (`bot_guild_share`). The rest stay unguilded, as
  many players did.
- **Number of guilds:** about one per 22 member slots. There are none until a realm has 8
  members to place (the classic `guild_num` of 8 founders).
- **Guild sizes:** a Zipf-like spread (weights 1/(i+1)^0.8), so a few big guilds and many small
  ones. No guild targets fewer than 8.
- **Charters** follow a fixed pattern by size order: the largest guild is RvR, the next Leveling,
  then Social, Raiding, and so on. Every realm gets a mix.
- **Placement:** unplaced bots join in a fixed order (a hash of their id) at each check. Each goes
  to the guild with the largest shortfall, weighted by charter fit. **A bot already in a guild is
  never moved** by formation.
- **Ranks:**
  - the founder (highest level when the guild forms) is rank 0;
  - about 1 member in 12 becomes an officer (rank 1, at most 3);
  - everyone else is rank 9.
  - If the leader is retired, the highest-level member takes rank 0.
- **Names:** invented, realm-flavored and period-style; never a real guild's name. Examples:
  - Albion: "Order of the Silver Hart", "Avalon Wardens"
  - Midgard: "Sons of the Frost Wolf", "Mjollner Oath"
  - Hibernia: "Clann na Darach", "Circle of the Moonlit Grove"

  Some are casual, as many 2003 guilds were ("Pie and Pints", "Tavern Regulars"). Names are
  unique on the server.
- **Rank titles** are set by charter (for example Warlord, Captain, Soldier, Recruit for RvR).
- **When it runs:** 90 seconds after start, then every 10 minutes. It reads the roster and writes
  only its own two tables (below) and new `Guild`/`GuildRank` rows, so it never competes with the
  bots' own status saves.

### 3.3 Storage

| Table | Columns | Meaning |
|---|---|---|
| `offline_bot_guilds` | GuildId, Realm, Charter, Ordinal, CreatedUtc, FounderBotId | marks a guild as bot-run |
| `offline_bot_guild_members` | BotId, GuildId, RankLevel, JoinedUtc | one row per guilded bot, **including bots in your guild** |

- The guilds themselves are ordinary `Guild`/`GuildRank` rows.
- **Release builder:** empties both tables, deletes every non-starting guild and its ranks, and
  removes the three settings so a release ships with bot guilds off. This also closes an existing
  gap: a guild created in a played install would otherwise ship.
- **Progress transfer:** carries both tables with `offline_world_bots` and `Guild`. They are
  listed as optional tables (`OptionalProgressTables`), because a server creates them on its first
  start; a database that never ran this version simply has nothing to carry.

### 3.4 In game (phase 1)

- **Over its head:** a guilded bot shows its guild name to its own realm.
- **Guild window and `/gc who`:**
  - list bot members with level, class and zone (or "Offline");
  - for a bot guild, you see its members only if you're in it.
- **`/ginvite` on a bot** (targeted or by name), into your guild. The bot accepts if it is:
  - of your realm and alive;
  - not in combat;
  - not a leader or officer of its own bot guild;
  - within 10 levels of you.

  It then leaves its bot guild, joins yours at your guild's lowest rank, and says so. If it
  declines, it says why in /say.
- **`/gc remove <name>`** works on bot members of your guild.
- **Formation leaves bots in your guild alone.**

### 3.5 Later phases (not built yet)

1. **Social:**
   - guild chat lines from the bot-voices corpus (bots only "talk" in guild chat when a real
     member can hear);
   - bots answer your `/gu`;
   - bots greet guildmates;
   - guild-based memory and loyalty.
2. **Grouping:** bots prefer guildmates when forming groups; Leveling guilds pick shared camps;
   bot guild officers invite you to their guild (a yes/no dialog).
3. **RvR:**
   - RvR guilds muster and raid together;
   - they claim keeps and towers (needs a bot claim path; `Claim` takes a `GamePlayer` today)
     and defend their claims.
4. **Economy:**
   - dues from bots' real coin loot into the guild bank (the owner's real-economy rule holds);
   - guild buffs bought with merit or bounty points;
   - emblems on bot cloaks.
5. **Guild houses and alliances.**

### 3.6 Settings (default off)

| Setting | Default | Meaning |
|---|---|---|
| `bot_guilds_enabled` | False | Formation, binding and bot invites. Off keeps every bot guildless and today's behavior. |
| `bot_guild_share` | 0.70 | share of eligible bots placed in bot guilds |
| `bot_guild_min_level` | 5 | lowest level that joins a bot guild |

**To turn on:**
- **Script:** `python tools/claude-version/set_bot_guilds.py --on --apply`, with the server
  closed. It backs up the database first.
- **In game:** with GM rights, `/serverproperties refresh` after changing the database.

## 4. Tests

**Automated (`UT_AutonomousBotGuilds`):**
- guild counts and sizes;
- the charter pattern;
- names are unique, in-realm and pass the format check;
- placement is stable and deterministic and respects level and realm;
- ranks;
- invite rules;
- bot members can be added to and removed from a `Guild`.

**In game (owner):**
- turn it on and log in after 10 minutes;
- see guild names over your realm's bots;
- `/ginvite` a bot;
- check the guild window;
- `/gc remove` it.

## 5. Status

Phase 1 is on `feature/bot-guilds`. Automated test results are in the CI run. **Nothing has been
checked in game yet.**
