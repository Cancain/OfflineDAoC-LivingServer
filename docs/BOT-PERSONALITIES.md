# Bot personalities, voices and debates: design and status

Goal: autonomous gamebots that feel like different people. Some grind, some hang around town, some
go looking for trouble, and each one writes in its own style. These are the "Social Expansion"
features, alongside [BOT-GUILDS.md](BOT-GUILDS.md).

They affect only **autonomous gamebots**. Companion bots (`/spawn`, `/raid`) and real players keep
today's behavior. Every part ships **off**. With all of it off, bots behave exactly as in stock 0.36.

## 1. Switches

| Setting (`ServerProperty`, category `bots`) | Default | What it does |
|---|---|---|
| `bot_personalities_enabled` | False | Personality types and traits tilt how bots spend their time (section 2). |
| `bot_voices_enabled` | False | Bots say lines from the bot-voices corpus in their own writing style (section 3). |
| `bot_voices_debates` | True | When voices are on, bots hold debates and long threads in /faction (section 4). |

To change them, use the launcher's **Social Expansion** tab (with the server stopped; it applies at the next start). The same switches are in a script, for those who prefer it: close the
server, launcher and game, then run (Python 3):

```
python tools\claude-version\set_bot_social.py                       (show the settings)
python tools\claude-version\set_bot_social.py --all on --apply      (all three on)
python tools\claude-version\set_bot_social.py --debates off --apply (one part off)
python tools\claude-version\set_bot_social.py --all off --apply     (back to stock behavior)
```

Without `--apply` the script only shows what it would change. With `--apply` it backs up the
database first (`runtime/server/deployment-backups/bot-social-<time>`) and reads the values back.

In game, target an autonomous bot and type `/personality` to see its type, traits and voice.

## 2. Personalities

A bot's personality is fixed from its database id, so it never changes between logins and
needs no new saved data.

### 2.1 Types

| Type | Share | In short |
|---|---|---|
| Leveler | 28% | grinds, short town breaks, likes full camps, often goes solo |
| Socialite | 20% | long town breaks, wants groups, chatty |
| Daredevil | 20% | dungeons, the harder cons of its legal range |
| Explorer | 16% | new zones, prefers solo |
| Crafter | 12% | long town breaks, avoids RvR, easy camps |
| NoLifer | 4% | barely stops, wants groups, dungeons |

Each bot also has five traits from 0 to 9 (curiosity, risk, sociability, patience, chattiness),
drawn within its type's range, so two Daredevils still differ.

### 2.2 What a personality changes

Every change is a **tilt** on a choice the bot already makes. The owner's hard rules (legal camps,
level ranges, real loot, selling only at natural breaks, earning armor, DF open to solo bots) are
never bypassed.

| Choice | Today | With personalities |
|---|---|---|
| Town break at a task boundary | 15% for every bot | about 4–37.5% by type, scaled by sociability (the realm average is about 16–17%) |
| Town break length | 15–30 minutes | ×0.7 (Leveler, NoLifer) to ×1.5 (Socialite), at least 5 minutes |
| Goal (solo, group, RvR...) | one draw from the configured mix | a chance to **re-draw from the same mix** when the type dislikes the first goal; nothing is forced or banned |
| Dungeon or outdoors | the configured dungeon preference | 60% (Crafter) to 170% (Daredevil) of it; a group uses its leader's |
| Which outdoor camp | weighted by live spawns | also weighted by taste: Daredevils like yellow and orange cons, Explorers like zones they haven't visited in 6 hours, Levelers like full camps. Every legal camp keeps at least 10% weight |
| How often it chats | the normal rate | ×0.25 to ×1.56 by chattiness (the realm average stays about the same) |

Zone memory is kept in memory only (32 zones per bot, forgotten when the server restarts).

## 3. Voices

When voices are on, a bot's chat comes from the corpus in
`source/server/GameServer/bots/autonomous/data/chat/` (842 lines and 296 scenes, written for
2002–2003; see [bot-voices/DESIGN.md](bot-voices/DESIGN.md)). The corpus is built into
`GameServer.dll`. Nothing is generated freely.

**Choosing a line:**
- by kind (ambient, lfg, trade, rvr, camp, reply, ding, death), realm, class, level and situation
  (in a group, solo, in town, in a dungeon, in RvR, at a camp, traveling, just leveled, just died,
  bag full)
- lines written for a personality type are three times as likely for that type and never used by
  other types
- replies to you match the intent the chat model reads from your message
- no line is repeated in a realm within 6 hours

**Writing styles** (fixed from the bot's id): plain 35%, terse 25%, chatty 20%, proper 15%,
typo-prone 5%.

**Where voices are heard:**
- ambient chat that a bot starts, in /say or /faction
- bot replies to players and to other bots (directed questions and knowledge answers keep today's
  answers)
- "ding" (35% chance) and death (25% chance) lines in /say, only when you are nearby

When no corpus line fits, the bot uses its old line.

**Not done yet:** lines that name you, a place you met or your class (`{player}`, `{place}`,
`{player_class}`) need bot memory of the player. Those lines are skipped for now. The greet,
thanks, gossip and grudge lines are in the corpus but not used yet.

## 4. Debates and long threads

When voices and debates are on, each realm's bots play scenes from the corpus in /faction:
- one scene at a time per realm, 30–45 minutes apart, the first 5–10 minutes after the server
  starts
- only while a player of that realm is online
- the cast is chosen from online bots of the realm within 5 levels of the scene's band, with a
  role's required class always kept and its personality type preferred
- a scene starts only if every required line can be said (a "price check" scene doesn't start when
  its speaker carries nothing)
- 3–10 seconds between lines, like typing
- if a speaker goes into combat, dies or logs out, another fitting bot takes the part, or the line
  is skipped; with fewer than two speakers left, the scene ends
- no scene repeats in a realm until all of its fitting scenes have played. The heard list is saved
  in `offline_bot_scenes_heard`, so it survives restarts. The release builder empties this table.

While a scene runs, bots don't start other /faction chatter in that realm.

## 5. Status

**Automated tests** (`UT_AutonomousBotPersonality`, `UT_AutonomousBotVoices`) cover:
- the type shares and the trait ranges
- the tilts and their averages
- the corpus loading from the DLL
- slots, tags, era words and lengths
- line choice, writing styles and the no-repeat window
- debate casting, scene choice and pacing

**Not yet checked in game.** The tests don't show how the realm feels after a few hours of play,
or how often lines repeat in practice. Things to watch when testing:
- towns busier or emptier than in stock 0.36
- bots stuck re-drawing goals
- debates that talk over each other
- lines that don't fit the moment
