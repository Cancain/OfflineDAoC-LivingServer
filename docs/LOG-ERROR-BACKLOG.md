# Log error backlog

Errors and open problems collected for later fixing. Each entry has the evidence (log message, count, when), what we
know, and a suggested fix. Nothing here is fixed yet unless it says so.

**Source of the 2026-10-27 entries:** `runtime/server/logs/server.log` on the owner's PC (playable-v0.36c), four server
starts that day:

| Start | Build | Notes |
|---|---|---|
| 05:43 | af39287 | |
| 08:12 | dabdd13 | |
| 09:17 | b062980 | |
| 11:17 | a058136 | classic launcher |

The logs cover about six hours of server time, with Claudecheck (Albion), Claudemid (Midgard) and Claudehib (Hibernia)
playing parts of it. Counts are for the whole log. Startup errors repeat once per start, so 4 means "every start".

## Priority 1: crash in the bot AI

### NpcService NullReferenceException in `BotBrain.BotState_Aggro.Think`

**Status: fixed in code 2026-10-27, not yet deployed.** Both properties now read their field once, and the ordered pull is
cleared only if it hasn't changed (`Interlocked.CompareExchange`). Watch the next long run for a repeat.

- **Seen:** once, 10/27 07:50:51, build af39287. The service caught it and removed the bot from the world:
  `RemoveFromWorld ... GameBot name=Roisellin ... reg=248`. Region 248 is a realm raid dungeon.
- **Stack:**

  ```
  Critical error encountered in NpcService: System.NullReferenceException
    at DOL.AI.Brain.BotBrain.BotState_Aggro.Think()  BotBrain.cs:line 2935
    at DOL.AI.Brain.BotBrain.Think()                  BotBrain.cs:line 1442
    at DOL.GS.NpcService.TickInternal(ABrain brain)   NpcService.cs:line 71
  ```

- **Code at that line (unchanged since af39287):**
  `if (_brain.ActiveOrderedPullTarget == null && (!_brain.HasAggro || (!_brain.HasCommittedDungeonPull && ...`
- **Likely cause (not confirmed):** a check-then-use race in `HasCommittedDungeonPull` (BotBrain.cs ~190). It reads
  the field `_committedDungeonPull` twice: a null check, then `.IsAlive` and `.CurrentRegion`. `ClearAggroList()` sets
  that field to null, and `CommitDungeonPull` is called from five other files: AutonomousDefensivePull,
  AutonomousDungeonTraversal, AutonomousWorldBotController (x2) and AutonomousBotGroupCoordinator. A clear between the
  two reads gives exactly this NRE. `ActiveOrderedPullTarget` (~776) has the same double-read pattern on
  `_orderedPullTarget`.
- **Suggested fix:** read each field once into a local
  (`var pull = _committedDungeonPull; return pull != null && ...pull...`) in both properties. Add a unit test that
  clears the pull between reads if a seam allows it.

## Priority 2: errors during play (not startup)

### Duplicate merchant page/slot

**Status: fixed in code 2026-10-27, not yet deployed.** The fix is in the server, not the data: `MerchantTradeItems.Layout`
lays each list out once and caches it for five minutes. The rules:

- Rows are read in a stable order.
- A copy of an item already in the list is dropped.
- A different item in a taken slot moves to the first free slot from its own page on.

The window, buying (`GetItem`) and `GetAllItems` all use that one layout, and GM `/merchant articles` edits clear the
cache. One `MERCHANT_LIST_TIDIED` info line per list replaces the error spam.

On the owner's world data: 51 lists, 1,818 copies dropped, 118 items moved to free slots (they could be hidden before),
none without room, and every item still shown. No database rows change, so there's no world update to ship. The data could
still be cleaned in a later release world.

- **Seen:** 361 lines today, 2,076 on 2026-10-22, so this predates the Living Server work. Logged when a merchant list
  loads during play:
  `two merchant items on same page/slot: listID=HibWeaponMerchant5 page=2 slot=6..9`
- **Lists affected today (lines):**

  | List | Lines |
  |---|---|
  | HibWeaponMerchant5 | 224 |
  | AlbWizardStaffs | 80 |
  | AlbTheurgistStaffs | 20 |
  | AlbSorcererStaffs | 20 |
  | 44ac972a-7aab-4d9c-8c2e-2c0fa5313c6a | 12 |
  | HibMetalBarMerchant | 5 |

- **Effect:** one of each pair is probably not shown or not sellable. No crash.
- **Suggested fix:** a data fix in `merchantitem` (renumber the duplicate slots). It goes in the release world defaults so
  new installs get it, and in a world update for existing installs (`make_patch.py`). Check that the bots' vendor upgrades
  (AutonomousBotEconomy) still find the items.

### Live dashboard snapshot: access denied

**Status: fixed in code 2026-10-27, not yet deployed.** The move is retried up to 4 times, 100 ms apart, on the dashboard's timer
thread. If the file stays locked, a one-line warning replaces the stack trace.

- **Seen:** 5 times, e.g. 06:10:45 and 06:30:45 (build af39287):
  `Live bot dashboard snapshot failed ... System.UnauthorizedAccessException: Access to the path is denied.
  at AutonomousBotDashboard.Publish ... line 120 (File.Move)`
- **Likely cause:** the launcher reads the snapshot file at the moment the server replaces it (Windows file lock).
- **Suggested fix:** retry the move once or twice after a short wait, or use `File.Replace`. Log a warning with no stack.

### Double world-enter disconnect (new client)

- **Seen:** 07:15:11. Two PLAY clicks sent two world requests:
  `Object is already in "Midgard"` -> `Failed to add player to world: ... Claudemid` -> `player.Delete()` and the client
  hung on "Entering the world...".
  Also 06:20:57 `GameClient.Player is being replaced but hasn't been deleted yet (current: ... Claudecheck ...)`.
- **Status:** the new client now ignores repeat PLAY clicks for 10 seconds (commit c5a7724). That isn't deployed yet,
  since it is a new-client file.
- **Still open:** the server could ignore a second world-init for a player who is already entering, instead of failing
  and dropping the client.

## Priority 3: errors at every startup (world data)

These print at each server start (counts are about 4x the per-start number). They predate this work. None stops the
server. Fix them as data clean-ups when convenient.

| Count | Source | Message | Likely meaning |
|---:|---|---|---|
| 928 | SkillBase | `LineXSpell Spell Adding Error: key not present, Line Item Effects, Spell #` | Spell-line rows point at spells missing from `spell` |
| 16 + 16 | SkillBase | same, Lines Mundane Poisons / Potions | same |
| 168 | NpcTemplateMgr | `No npctemplate with ID # found` (5232525, 60166758, 10001, 12967, 604021, 60167801 ...) | Mobs or spawns point at missing templates |
| 60 | NpcTemplate | `Tried to load a null spell into NPC template # spell ID: #` (incl. spell 0) | Template spell lists with bad IDs |
| 140 | DoorMgr | `Failed to register door in pathfinding provider, possible navmesh/object location mismatch` (Postern Door, Keep Door, Relic Gate, door) | Doors off the navmesh. Check per door; no global navmesh rebuilds |
| 8 | Region | `Error loading NPC ClassType: DOL.GS.Scripts.RPTradeInMerchant` (GameNPC used instead) | The class doesn't exist in this build |
| 4 | ScriptMgr | `LoadCommands: An item with the same key has already been added. Key: &tc` | Two command handlers claimed `/tc`. **Fixed 2026-10-27 (not deployed):** `/transfercorpse` lost its `/tc` alias; `/tc` is the Realm Exchange teleport |
| 4 each | ScriptMgr | `Couldn't find a SpellHandler constructor for UniPortal / UniPortalKeep / ArmorFactorBuff` | Spell types without handlers |
| 4 | SkillBase | `Requested value 'ground' was not found ... spellid` | Bad enum value in a spell row |
| 4 each | LootGeneratorOneTimeDrop | `Can't find MobName Hrodrek / Dob / Murgar / Neese / Cheshire` | One-time drops for mobs not in the world |
| 4 each | LootGeneratorTemplate | `ItemTemplate: <item> is not found, referenced from loottemplate: Apocalypse / Golestandt / Dura'ek / Maldahar / Moran / Morvalt` | Loot tables point at missing items |

Related warnings at startup:
- `GameNpcInventoryTemplate: Error adding NPC equipment` (201)
- `Failed loading NPC inventory template: abomination_fiery_sword` (50)
- `Clothing Manager: Guard Inventory is null for GuardCorpseSummoner` (96)
- `Couldn't find a zone for (... ColialtAdds / living entombed ...)` (45+)

## Warnings worth a look (not errors)

These are mostly the bots' own diagnostics, counted over about six hours:

| Count | Warning | Note |
|---:|---|---|
| 6,351 | `AUTONOMOUS_DEATH_ROUTE_REPLAN` | e.g. a level 16 necromancer with 13 deaths to "living entombed". Bots dying repeatedly on one route. Check the worst offenders. |
| 799 | `AUTONOMOUS_BETWEEN_TASK_TIMEOUT` | |
| 597 | `AUTONOMOUS_GROUP_MATCHMAKING_TIMEOUT` | |
| 317 | `AUTONOMOUS_GROUP_RESURRECTION_TIMEOUT` | |
| 292 | `BOT_PET_STUCK_RECOVERY` | |
| about 2,600 | "Long tick" timing warnings (MovementService, NpcService, TimerService, AttackService) | Mostly 40-60 ms, some NpcService ticks of 190-270 ms on navigation. Keep an eye on them. |
| 103 | SQL queries over the time budget | |

**Memory:** no leak seen. Live heap stayed at 1.6-1.8 GB from 05:48 to 11:48 across restarts, and working set at
5.8-7.0 GB.

## Open from the in-game checks (2026-10-27)

Not log errors, but found while playing and not yet fixed or verified:

- **Rumours have never fired in game.** There was no `RUMOUR_NAMED` or `RUMOUR_KEEP` in about six hours with players
  online. Diagnostics were added (`RUMOUR_KEEP_CHECK`, `RUMOUR_NAMED_CHECK`, commits 8d4a31e and 86edd19) and are not yet
  deployed. Next run: check whether keeps ever drop under 30% of their guards and whether rare named respawn while a
  player who would care is online.
- **Deeds have never been earned in game:**
  - Ganked needs 4+ enemies within 2,000 units; a death to 3 Hibernians at Hadrian's Wall didn't count.
  - A solo named kill needs yellow con or harder, which a level 50 can't easily find.
  - `PLAYER_DEED_SKIP` logging (fd6dbbd) is not yet deployed.
- **No way to hand a beggar coin in the new client.** The server takes gifts, but the client has no obvious give or
  trade action.
- **Rage-quit return line not yet seen.** Ederorred's rage quit ran out at 09:05 and survived restarts, but he hadn't
  logged back in by the last check. He returns on his next scheduled login.
- **Classic client test not run.** At 11:18 the classic client was logged in, but screen control stopped when the PC's
  display went to sleep.
