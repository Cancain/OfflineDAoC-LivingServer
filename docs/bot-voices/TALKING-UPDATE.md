# The talking update (Living Server Beta 1.1)

Bot chat in Beta 1.0 had three problems. Bots said things that weren't true: a Hibernian in Ardee asked about an
Albion dungeon, "heading into myrkwood" came from anywhere in Midgard, and Darkness Falls lines came from inside Tomb
of Mithra. Every line also stood alone: a player who answered a bot's question got no reply, and a "why?" got nothing.
And bots in the player's group said nothing during a fight. The talking update fixes these, and makes realm chat
sound like a busy server.

It affects **autonomous gamebots** only. Companion bots (`/spawn`, `/raid`) and real players are unchanged. Content
rules for new lines are in [TALKING-UPDATE-CONTENT.md](TALKING-UPDATE-CONTENT.md).

## Settings

All are server settings, category `bots`. The first three are in the launcher's Living Server tab.

| Key | Default | What it does |
|---|---|---|
| `bot_voices_enabled` | **True** (was False) | Corpus lines in each bot's own style. Everything below needs it. |
| `bot_living_memory` | **True** (was False) | Bots remember grouping with you, your rezzes and rude words. Bot tells need it. |
| `bot_living_grats` | **True** (was False) | Grats on a ding in /group, /say and, for a 50, /faction. |
| `bot_voices_tells` | True (new) | Bots now and then start a tell with you (below). |
| `bot_voices_chat_rate` | 1.0 (new) | How much bots talk unprompted: 0 (they only answer) to 3. |

Only these chat parts are on by default. Personalities, guilds and the other Server life parts stay off.

**Worlds that ran an earlier build.** The server keeps a setting's stored row, so on its own the new default would
never reach a world that has already run. On the first start of 1.1 the server switches on, once, each of the three
settings whose row it wrote itself with the old default (`LivingServerSettingsUpgrade`; the server log says which).
Rows saved in the launcher are left as they are. The row `living_server_settings_version` records that the switch ran.
To keep a part off, switch it off again in the Living Server tab; it is not switched on a second time.

## What changed

### 1. Bots only say what is true

- **Places.** `data/chat/places.json` lists about 140 zones, towns, dungeons, capitals, frontiers and battlegrounds
  with their realm and the zones that count as being there. A line that names a place must either claim the speaker
  is there or on the way (`@needs at:<place>`, `going:<place>`, `near:<place>`), or say it is only talking about it
  (`@about place`). The build (`tools/bot-voices/build_corpus.py`) rejects a line that names another realm's zone,
  town or dungeon. Frontiers and capitals are exempt. The speaker's `at:` and `going:` flags come from its zone,
  region and travel destination (`AutonomousChatPlaces`).
- **News.** `AutonomousChatNews` watches keeps changing hands, relics taken and returned, Darkness Falls, realm raids
  won or wiped, and sieges. Lines about a keep, relic, raid or Darkness Falls need the flag that makes them true:
  `defending`, `attacking`, `keep_lost_recent`, `relic_won_recent`, `df_ours`, and so on. The flag fills the line's
  `{keep}`, `{relic}` or `{boss}` with the real one. Defenders hear of a siege only once the walls are hit or their
  defense is called.
- **Experience and roles.** `{bubbles}` is the speaker's real xp in the level. `xp_low`, `xp_mid` and `xp_high` gate
  "almost there" lines. `is_healer`, `is_tank`, `is_caster` and `is_support` gate role claims, and `newbie` (1-14) and
  `veteran` (40+) gate experience talk.
- **No fallback lies.** With voices on, a bot with nothing true to say stays quiet. It no longer falls back to the
  old formal lines ("How fares everyone across the realm?").
- **Enemy sightings.** "Where are the mids?" is answered from what the realm has seen. Frontier bots put the enemies
  they see on the news board, with how long ago, and enemies within sight of a bot or player of the realm also count.
  Before, the answer came from where every enemy gamebot was.
- **Lines that promised what the server can't do** are off. A bot can't invite a player, so the "we have room at
  {camp}, want in?" and "sending an invite" lines are never said.
- **The simulator found more.** It turned up "my pet has better gear than me" from wizards (now pet classes only), a
  solo bot apologizing to "my healer" (now in a group only), and a scout sitting "to get my power back" (now health).

### 2. Conversations follow on

`AutonomousChatThreads` remembers the last 8 bot lines per channel (`/faction`, `/say` per region, each tell pair,
`/group`):

- A **follow-up** within 90 seconds of a bot's line ("why?", "rly?", "how so", "wdym", "who?", "where?") is answered
  by that bot. The answer fits the kind of line (a boast, complaint, joke, news...), and "where?" gets where the bot
  really is.
- An **answer** to a bot's open question within 75 seconds is thanked by the asker 85% of the time ("ty, heading
  there"), and the other bots leave it alone. A line that names another bot is not taken as an answer.
- **Tells** continue the exchange for 4 minutes: a follow-up to the bot's last line, or thanks for an answer.
  A tell's reply is worked out when it is sent, so "where are you?" gives where the bot is then, not where it was
  30 seconds before.

### 3. News in the bots' own words

When a keep falls, a relic moves, Darkness Falls changes hands or a realm raid wins or wipes, a bot tells /faction,
50-80 seconds later. A bot that was there speaks as a witness ("we just lost the gate at {keep}, they had rams");
otherwise it's heard ("heard we lost {keep}"). Others react ("again??", "omw"). When a herald notice already covered
the event, the bot doesn't repeat it, and with voices on the herald notices themselves are said by a bot where one
fits.

### 4. Combat calls in your group

`AutonomousBotCombatCalls` runs once a second for each gamebot in the player's group. Every call comes from real
state:

| Call | When |
|---|---|
| pull ("inc", "here it comes") | a fight starts, 35%; said by a bot in the fight, a tank first. The player usually pulls, so no "pulling now", and "inc 1" only with one enemy |
| add ("add, add") | more enemies on the group than before, at most every 15 s, 75% |
| low_hp ("heal me") | the bot's health drops under 30% in a fight, once until it is back over 50% |
| oom ("oom") | in a fight, a caster's or healer's power drops under 15%, once until it is back over 40% |
| mez, root, stun | the bot cast it and it landed (the target is mezzed, stunned or snared); a mez only with two or more enemies |
| taunt, heal_big, rez | the bot is casting that spell now |
| wipe ("run!") | half the group has died in this fight (groups of 3+), once |
| kill / rest ("gj", "med up") | a fight ends without a wipe, rest more likely when the group is worn |

The group hears at most one call every 3.5 seconds (a wipe call always goes out), and each bot speaks at most every
8 seconds. A gamebot that joins your group says hello in /group most of the time.

### 5. Bots start tells (rarely)

Needs voices, memory and `bot_voices_tells`. The first tell can come 4-10 minutes after you log in, then at most one
every 25-45 minutes, and a given bot tells you at most once every 6 hours:

- **friends** (bots that grouped with you or that you rezzed, not ones you insulted): hello, thanks for the group at
  {place}, the realm's news, or a hand if you are under level 20 and at least 8 levels below them;
- **guildmates** in a bot guild you belong to: small talk;
- **a solo bot of your level** (±2) in your zone, within 6,000 units, while you are ungrouped: a duo offer.

A friend standing next to you greets you in /say instead. A player's **/lfg** may also get a duo offer by tell from a
solo bot within 2 levels, the same zone first (this needs voices and `bot_voices_tells`, not memory). A bot busy with a
siege, a relic, a raid or a horse route says so instead of "send me an invite". Answer "sure" and the bot tells you how to group ("sure, send me an
invite": you invite, because a bot can't). "Nah" gets "np, maybe later".

### 6. A busier, more natural realm chat

- The gap between bot-started /faction lines is 2-4 minutes at 120 bots of the realm online, an ordinary hour and
  rate 1. It is shorter with more bots online (√ scale, 0.5-1.8×) and in the evening (18-23 h, 1.35×), and longer
  late at night (2-7 h, 0.55×) and in the morning (0.85×). It never drops below 40 seconds. `/say` gaps follow the
  hour and the rate. `bot_voices_chat_rate` scales both, and each bot's own chattiness.
- Most `lfg` lines go to the realm's **/lfg** channel (`[LFG] Name (level, class): ...`) and most `trade` lines to
  **/trade**, as players used them, instead of /faction. The new client shows both with /faction chat.
- Guild template lines, knowledge answers in /gu and /group, join replies and "where are you?" answers are written in
  each bot's own style (lower case, typos, abbreviations).

### 7. Bots read what you say, and answer it

An audit ran realistic player lines through the reply path, each labelled with what a sensible player would answer.
Factual questions drew remarks on the topic ("is thid open for lvl 21" drew "if you see the zerg coming, call it
out"), follow-ups were missed, "inc" read as income and tells about groups as invitations. Changes:

- **Questions get real answers.** About the bot, when it is asked by name, by tell or in your group: its level, class,
  realm rank, speed, potions, guild, main or alt, epic, how long it has played, whether it is busy, its plans (by
  personality), and where its gear came from (worn pieces, and how many a crafter made). About the world: a place's
  monster levels (the 20th-80th percentile of each zone's monster levels in the world data, written to `places.json` by
  `tools/bot-voices/place_levels.py`), battleground brackets, who holds Darkness Falls, the relics and keeps, and a few
  commands (/stuck, /anon, /bind, /played, /relic). Any other factual question gets an honest "not sure" now and then,
  never a remark on its topic.
- **The bot's name is not part of the line.** "torvald u still a thane?" is read as "u still a thane?" by Torvald.
- **More of the conversation follows on**, in /faction, /say and now /group: "which bridge", "how long did that take",
  "the one by the inn?", "whered they go", "o ya what stats", "into what"; "no thanks" to a bot's offer; "ty" to the bot
  that just helped (not for its own "gz" or "np"); a laugh to the joker; "x" or "me" to a bot's call for a group.
- **New kinds of line**: good news ("finally hit 50") gets grats, an offer ("need buffs?") thanks, "wait for me" an ok,
  "wb" a thanks, an order ("heal me") an "on it" or an honest "cant heal, im a thane", a warning a "ty for the heads up",
  real-life talk (late nights, school, food, the computer, pets, weather, TV, work, a sore back) a reply in kind.
- **Fewer misreadings**: "inc" as income, "group" only talked about ("my old group quit", "love this group"), sarcasm
  ("thanks for the train"), insults aimed at a class rather than a person ("ppl say spiritmasters are useless"), "pc"
  as a computer, school "class", goodbyes with thanks in them, a brb at the end of a line.
- **Group requests**: "want to group?" in /say or by name gets the bot's answer with its real reasons (already grouped,
  on a keep or relic, too far, a level gap of more than 8). An /lfm is answered only by bots of the role it needs and
  within 6 levels.
- **When you die in a group**, a groupmate says so, a healer first ("rez coming, dont release").

**How well it reads, measured.** These are automated measures of how a line is *read* (which route it takes), not
of the reply text, and not checked in game:

| Line set | Before the audit | After |
|---|---|---|
| The 320 audit lines (the fixes were made against these) | 47% | 96% |
| Fresh set 1, 160 lines written blind, first run | — | 62% |
| Fresh set 2, written blind after the fixes for set 1, first run | — | 65% |
| Fresh set 3, written blind after the fixes for set 2, first run | — | 62.5% |

The tuned rates overstate what new chat gets: on lines nobody tuned against, about **two in three** are read the way a
player would expect. The rest split roughly evenly between no reply, an honest "not sure" and a reply that misses (12-16%
of fresh lines on sets 2 and 3, against 21% on set 1). The code from before the audit was not measured on fresh lines. About six of set 3's misses are a labelling difference (a
"gz" for the bot's own ding is answered "ty", as it should be, but was labelled as the player's news). Sets 1 and 2 were
then fixed against and are kept as a regression test; set 3 (`tools/bot-voices/eval/fresh_lines_3.json`) is kept
untuned. Word rules have reached about their ceiling here; reading more of free chat right would need a different
approach (a trained model on many more labelled lines), not more rules.

To measure a new blind set: `TALK_AUDIT_IN=<lines.json> TALK_AUDIT_OUT=<misses.txt> dotnet vstest Tests.dll
--Tests:MeasureReadRate` (each line `{text, channel, context?, expect, to?}`; `to` is the bot named in the line).

## Content

The corpus went from 2,326 to 3,573 lines (`talking_audit.lines` holds the audit's reply sets). These files are new: `news.lines`, `news_replies.lines`, `tells.lines`,
`memory_more.lines`, `combat_calls.lines`, `lfg_real.lines`, `followups.lines`, `closings_more.lines`, `camp_more.lines`,
`guild_more.lines` and `experience.lines`. The existing files were annotated with place, news, xp and role flags,
and a few were reworded or removed.

The `lfm` lines (a bot group looking for {need} at {camp}) are written, but they are not said yet. A bot group can't
take a player, so a player who answered one would have nowhere to go.

## Tests

- `UT_TalkingUpdate`: 79 cases, covering places, `near:` needs, news topics and flag windows, siege flags and
  outcomes, sightings, bubbles, follow-up words, answers, yes/no, the thread log, combat-call rules and gaps, tell
  timing and fit, chat gaps, pull and add line fit, the one-time settings upgrade, and corpus coverage for every topic the code asks for.
- `UT_ChatSimulation`: an evening in each realm (30 openers with replies), a keep lost, a group fight and three
  conversations, played through the real corpus picker. It fails on a speaker naming another realm's zone, town or
  dungeon, an unfilled slot, or a keep named without news. Set `TALK_TRANSCRIPT=<path>` to keep the transcript.
- `UT_TalkingAudit`: the 320 audit lines (floor 93%) and the 320 holdout lines fixed after them (floor 92%), plus
  cases for names, threads, closings, self answers, place levels and world answers. `ChatAuditRoute` mirrors the live
  reply path for these; keep the two in step.
- All 3,681 tests in `Tests.dll` pass (2026-10-26, Linux, no game world). CI on Windows ran the server tests and the
  launcher tests on the branch.
- An independent review of the code (2026-10-26) found eight defects, all fixed: the defaults not reaching existing
  worlds, help offers answered as duo offers, "pulling" said after the player pulled, "mezzed" before a resist, relic
  notices lost for two realms, keep news told twice, a player's /lfg taken as an answer, and "oom" outside fights.

## Not checked in game yet

Everything above was tested without a running world. These need the PC:

1. /lfg and /trade lines show in the **original client**. The server sends chat types 0x23 and 0x24, which its own
   /lfg and /trade commands use. Also check how the new client shows them (mapped to the faction tab).
2. Combat calls in a real group fight: pull, add, low health, oom, a Bard's or Enchanter's mez (said only once it
   lands), a group heal, a rez after a death. Check that they are timely, not spammy, and say nothing outside a fight.
3. A keep taken in the frontier: a bot tells /faction in its own words about a minute later, and the herald text
   isn't said twice.
4. Ask "why?" right after a bot's /faction line, and answer a bot's question ("try spindelhalla"). Check that the
   right bot answers and the others stay quiet.
5. A friend's tell 4-10 minutes after login. A duo offer from a bot of your level nearby, and "sure" to it.
6. /lfg "lfg 20 cleric" while ungrouped: a duo offer by tell within about 20 seconds.
7. Chat volume over an evening with 900 bots per realm: /faction should feel busy but readable (no more than one bot
   opener every 40 s).
8. "Where are the mids?" while enemies are in the frontier and while they aren't.
9. The server log shows no `Bot voices:` warnings from the new code (combat call, world flags).
10. Start 1.1 on the owner's world: the log names the settings it switched on, and the Living Server tab shows them.
11. Ask a bot by name and by tell: "r u 50 yet", "what lvl is vendo caverns", "is df ours", "whered u get that armor",
    "u busy". The answers should be true of that bot and the world (its level, gear, the real owner of Darkness Falls).
12. Die in a group with a healer bot: one groupmate says so, the healer first. Give a bot an order it can't do
    ("heal me" to a thane) and one it can.
13. Answer a bot's call for a group with "x", and say "ty" right after a bot's "gz": the first gets a join answer, the
    second nothing.
