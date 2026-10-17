# Living Server

Part of the Social Expansion fork. The goal (Chris, 2026-10-16): make the autonomous gamebots feel
like players on a 2003 server, through continuity and consequence more than through more chat.

**Status:** built on `feature/living-server`. Automated tests pass (see "Tests" below).
**Not yet checked in game.** Every part starts **off**; with everything off the server behaves
exactly as before.

Only autonomous gamebots change. Your `/spawn` companions and real players are never affected.
Lines come from the bot-voices corpus (`living_server.lines` and `memory.lines`), in each bot's
own writing style. They work whether or not "Bot voices" is on, and they are only said where a
real player can hear them (your group, `/say` near you, your realm's `/faction`, a guild with you
in it).

## Switches

All are in the launcher's **Social Expansion** tab, card **LIVING SERVER**. Save with the server
stopped; they are used at the next start. The server keys (category `bots`) are:

| Switch | Key | Default |
|---|---|---|
| Bots remember you | `bot_living_memory` | False |
| Grats | `bot_living_grats` | False |
| Server firsts | `bot_living_firsts` | False |
| Rezzes and corpse runs | `bot_living_death` | False |
| Frontier alarms | `bot_living_alarms` | False |
| Nemeses | `bot_living_nemesis` | False |
| Bot schedule | `bot_schedule_mode` | `off` (also `session`, `clock`) |
| Breaks and linkdeads | `bot_living_breaks` | False |

**ALL OFF** in the tab switches every part off, along with the other Social Expansion features.

## What each part does

### Bots remember you (`bot_living_memory`)
- A bot of your realm remembers:
  - grouping with you (noted at most once per 30 minutes per bot);
  - you rezzing it;
  - you insulting it in chat (the chat model's "abuse" intent).
- Its mood toward you follows from that: friendly, neutral, or cool after insults.
- What it does with the memory:
  - **Greets you** when you pass within about 700 units: at most one greeting every 3 minutes, and
    the same bot at most every 45 minutes. Groupmates don't greet.
  - Sometimes **thanks you for an old rez or a good group**, naming the place.
  - **Answers you by name** when you talk to it. A cool bot gives you a short brush-off.
  - Now and then (every 30–60 minutes per realm) a bot that likes you **mentions you in
    `/faction`**, never one standing next to you.
- Memory is chat only. It never changes who groups with whom, and it never refuses you.
- Kept in the table `offline_bot_memory`.
- Not built: memory of heals and trades. Lines for them exist but are never chosen.

### Grats (`bot_living_grats`)
When you or a bot gains a level:
- 1–3 bots in the group say grats in `/group` (only when a real player is in the group).
- 0–2 bots standing nearby say grats in `/say` (only when a real player is near).
- At level 50, 1–3 bots of the realm cheer in `/faction`.

Each character gets at most one grats chain every 20 seconds. This is separate from guild grats
(bot guilds), which stay in `/gu`.

### Server firsts (`bot_living_firsts`)
- **What counts:**
  - the first character on the server, you or a bot, to reach level 50;
  - the first of each class to reach 50;
  - the first to each realm rank from 2 up.
- **How it's announced:** everyone gets one line on screen and in the system window. Other realms
  see "a Hibernian champion", not the name. In the achiever's realm, 1–2 bots cheer in `/faction`.
- **Recorded:** in `offline_server_firsts`, and shown in the Camelot Herald.
- **Turning it on in a played world:** titles someone already holds are marked "reached before
  records began" (no name, never announced). So the next character to get there isn't wrongly
  called the first.
- **Not built:** "first kill of a big named monster".

### Rezzes and corpse runs (`bot_living_death`)
- **When a bot dies:**
  - If a real player of its realm who can rez is within about 2,500 units, the bot asks that
    player for a rez by name, after a few seconds.
  - The rez classes are Cleric, Friar, Healer, Shaman, Druid, Warden and Bard.
  - The bot then waits the long release timer (90 s) instead of 20 s, even if you aren't in its
    group.
- **Releasing and being rezzed:**
  - A bot that releases may say it's running back from bind.
  - A bot in your group sometimes grumbles about resurrection sickness. Bots don't actually get
    the illness; this is chat only.
  - A rezzed bot thanks the rezzer by name. This replaces the old "My thanks... formation" lines
    for autonomous gamebots.
- **Bots rez you:**
  - An autonomous gamebot that can rez, and isn't in your group, rezzes you when you lie dead
    within 1,500 units of it.
  - You get the normal accept/decline box.
  - It never rezzes during a fight (its own or its group's). Only one bot works on a corpse at a
    time.
  - Groupmates already rezzed you before; that is unchanged.

### Frontier alarms (`bot_living_alarms`)
- **When:** a bot in the frontier or a battleground sees 3 or more enemy players or gamebots
  during its normal threat scan. It calls them in `/faction`, for example "inc 8+ mids at Caer
  Benowyc, healer, warrior, skald".
- **What it says:**
  - the head count is rough (exact up to 8, then 10, 15, 20);
  - up to three classes;
  - the place is the nearest frontier keep within 6,000 units, or the zone.
- **Limits:** at most one alarm per realm every 2 minutes, and one per place every 5 minutes. None
  while a `/faction` debate is running.

### Nemeses (`bot_living_nemesis`)
- **Recording:** a bot killed by an enemy player or enemy gamebot records the killer (pets count
  for their owner) in `offline_bot_nemesis`.
- **Complaining:** from the second kill by the same enemy, the bot may complain in `/faction`,
  once per 20 minutes at most.
  - Enemy names are hidden in the frontier, so it names the killer by race and class: "that troll
    berserker is camping Caer Benowyc".
- **Revenge:** when the bot later kills that enemy, it may gloat in `/faction`.
- **Herald:** the Camelot Herald's **Most Wanted** lists the enemies with the most recorded kills.

### Bot schedule (`bot_schedule_mode`)
- `off` (default): every bot stays online, as before.
- `session`: each bot plays sessions of 1–4 hours, with 20 minutes to 2 hours away. Timing is
  counted from server start. About two-thirds of the roster is online at any time.
  - No-lifers play longer and are away less; Socialites play a little longer.
- `clock`: follows your PC's clock like a 2002 North American server.
  - About 95% of the roster is online from 8 to 10 p.m.
  - About 20% at 4–5 a.m.
  - Weekends (from Friday 6 p.m.) are busier in the daytime.
  - The same bots stay on as the evening fills up; no-lifers stay up late.

**How logging out works:**
- Only bots that can leave without breaking anything log out: ungrouped, alive, out of combat, not
  casting, not on a stable route, not walking back after a release, not carrying a relic, not on a
  siege job and not in an RvR event force. A scheduled-off bot that is busy stays until it's free.
- At most 3 bots log out every 5 seconds.
- A bot may say goodnight first: in guild chat when a guild member can hear, otherwise in `/say`
  near you.
- Scheduled-off bots aren't logged back in until their schedule says so. When they return, some
  say hello. Nobody greets during the first 10 minutes after the server starts.

### Breaks and linkdeads (`bot_living_breaks`)
- **Breaks:** an idle bot (the same rules as logging out) now and then says "brb" and logs off for
  5–25 minutes, about once per 4 hours online. When it comes back it says "back".
- **Linkdeads:** a bot in a group with you rarely goes linkdead.
  - How often: at most once per group every 45 minutes, about once an hour of grouping.
  - What happens: it stands still and does nothing for 30–90 seconds. Another bot in the group may
    say "X went ld", and the bot comes back with "sry ld".
  - Never during a fight. Anything that attacks a linkdead bot wakes it at once.

## Camelot Herald

**CAMELOT HERALD** in the Social Expansion tab writes a news page from the game database and
opens it in your browser. It reads only and is safe while the server runs.
- **Where:** one self-contained file at `runtime\herald\herald.html`. Nothing is loaded from the
  internet.
- **What it shows:** realm points leaders, guilds, keeps held by enemies, relics, server firsts,
  Most Wanted, and recent realm events.
- **Releases:** the page names your characters, so the release builder never ships the `herald`
  folder.

## Data and releases

New tables, all empty in a release and carried by the progress transfer when both databases have
them:
- `offline_bot_memory`
- `offline_bot_nemesis`
- `offline_server_firsts`

Writes are batched off the game loop every 5 seconds, under the same database lock as bot status
saves. The release builder deletes every `bot_living_*` setting and `bot_schedule_mode`, so
releases ship with everything off.

## Tests

Automated (no running world):
- **Server, `UT_AutonomousLivingServer`:**
  - defaults are off;
  - schedule parsing, session lengths and online share, and how often a bot's state changes;
  - the clock curve and that clock mode keeps the same bots online;
  - mood rules, alarm head counts, race and realm words, first claims;
  - nemesis and alarm lines fill every slot; greetings follow mood;
  - this document lists every key.
- **Server, `UT_AutonomousBotVoices`:**
  - every Living Server kind has lines for every personality;
  - topic filtering;
  - the six-hour no-repeat window.
- **Launcher:**
  - `SocialExpansionSettingsTests`: the new keys and defaults match the server, the schedule mode
    is read like the server reads it, and ALL OFF;
  - `HeraldPageTests`.
- **Corpus:** `build_corpus.py --verify` and `check_runtime_names.py` in CI.

**Not yet checked in game.** Suggested checks:
1. Turn on **Grats**, group with bots and level: groupmates say grats in `/group`.
2. Turn on **Rezzes and corpse runs** on a rez class: a bot that dies near you asks you by name
   and thanks you after you rez it. Die near a bot healer that isn't in your group: it offers a
   rez and you get the accept box.
3. Turn on **Bots remember you**: group with a bot for a while, leave, and walk past it later. It
   greets you by name.
4. Turn on **Frontier alarms** and go to the frontier: `/faction` calls enemy groups, at most one
   every 2 minutes.
5. Set **Bot schedule** to `clock` and start the server at different times of day: the online
   count in the launcher follows the time.
6. Turn on **Breaks and linkdeads** and group with bots for an hour: watch for "brb" and "ld".
7. Click **CAMELOT HERALD**.
