# XP rates by level range

Two optional server settings let leveling speed change by level. For example, you can level at 3×
through the early game and 12× from level 35 to 50. **Both are off by default**, and the server
behaves exactly as before until you set them.

| Setting | Who it affects | When it is empty (default) |
|---|---|---|
| `xp_rate_by_level` | Your characters (real players) | `xp_rate` for every level |
| `bot_xp_rate_by_level` | Autonomous gamebots only | `bot_xp_rate` for every level |

## Format

Write each range as `first-last:rate`, with ranges separated by semicolons:
`1-19:3;20-34:5;35-50:12`

- **A single level** can be written without a dash: `50:2`.
- **Spaces** are allowed.
- **Decimals** use a dot: `1.5`, not `1,5`.
- **Rates** must be above 0 and at most 1000. A rate below 1 slows leveling down.
- **Ranges** may not overlap.

## How it applies

**Inside a listed range, its rate replaces the flat rate.** Levels outside every range keep the flat
rate.

| Case | Your characters | Autonomous gamebots |
|---|---|---|
| Base XP from monsters | Uses the range rate | Uses the range rate |
| Zone XP bonus | Uses the range rate | Uses the range rate |
| In RvR zones | Keeps `rvr_zones_xp_rate`, as before | Range rate × `rvr_zones_xp_rate`, as `bot_xp_rate` was |

- **Same parts as the flat rates:** like `xp_rate` and `bot_xp_rate`, the range rate multiplies the
  base XP of a kill and the zone bonus. Camp, group and other bonuses are added on top unmultiplied,
  as before. The per-kill XP cap is applied before any rate.
- **Which level counts:** the character's level when the XP arrives.
- **Not affected:** companion bots (`/spawn`, `/raid`) and Bounty Master rewards. Bounty rewards
  still use `xp_rate`.
- **An invalid setting is ignored:** the flat rate stays in use, and the server log says why once.

## The plan's values

These come from the Living World plan (model v4):

| Who | Levels 1–19 | Levels 20–34 | Levels 35–50 |
|---|---|---|---|
| You | 3× | 5× | 12× |
| Gamebots | 1.5× | 2.5× | 6× |

## Setting them

The helper script is in this fork, not in shadowofze's downloads. Copy
`tools/claude-version/set_xp_by_level.py` into your playable folder's `tools\claude-version\` first,
along with a server build that has these settings.

**Close the server, launcher and game first.** Then, from the playable folder:

```bat
python tools\claude-version\set_xp_by_level.py
python tools\claude-version\set_xp_by_level.py --player "1-19:3;20-34:5;35-50:12" --bots "1-19:1.5;20-34:2.5;35-50:6"
python tools\claude-version\set_xp_by_level.py --player "1-19:3;20-34:5;35-50:12" --bots "1-19:1.5;20-34:2.5;35-50:6" --apply
python tools\claude-version\set_xp_by_level.py --off --apply
```

- **The first line** shows the current settings.
- **The second** checks the values (a dry run).
- **The third** writes them, after backing up the database to `runtime\server\deployment-backups`.
- **The last** goes back to the flat rates.

The launcher's XP buttons still set the flat `xp_rate` and `bot_xp_rate`. Those flat rates are what
applies outside your ranges.

**Resets:**
- **The progress transfer tool resets the XP settings.** After a transfer into a new install it sets
  `xp_rate` and `bot_xp_rate` back to 1, and it now also clears both range settings. Set them again
  afterwards.
- **Public packages always ship with both settings off.** `build_release_036.py` clears them and
  checks that they are empty.

## Status

- **Automated tests:**
  - `UT_LevelRangeXpRates` covers parsing and the range lookup;
  - `UT_BotXpRateSeparation` covers bot scaling, including RvR zones;
  - on GitHub's Windows build (2026-10-11): 47 of 47 of these pass on their own, and the full
    server suite passes (2,674 of 2,674, without the 47 test classes that need installed game
    files).
- **In-game check:** not done yet. Check it by killing a few monsters at a level inside and outside
  a range and comparing the XP messages with the flat rate.
- **Code:** `source/server/GameServer/gameutils/LevelRangeXpRates.cs`, used by `GamePlayer` and
  `GameBot`.
