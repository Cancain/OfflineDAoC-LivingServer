# Offline DAoC 0.35 "Claude Takeover III"

0.35 continues from 0.34. It collects every fix and feature added since 0.34 in one complete
download: the classic quests with red map markers and a Quest Guide, the monster populations of
the period, new Summoner's Hall and Darkness Falls raid events, keep and relic sieges with siege
engines, battlegrounds, the classic frontier war map, and many gamebot and companion improvements.
Every single change is listed in the [changelog](../CHANGELOG.md).

It comes in two editions, from one download. They are the same game, and only the custom class
differs:
- **0.35b** includes the Hibernian **Sluaghbinder** class, for players and bots.
- **0.35** has the original Classic + SI class list only. The Hibernian Mauler slot is disabled,
  as in 0.32. Its game client now has every client improvement of 0.35b: the classic war map, red
  quest markers and the working QUEST GUIDE button.

## Downloading and starting

- **One full download**, as in 0.34. The helper fetches the game in parts, checks every part and
  unpacks one ready-to-play folder.
- **Your own account, world and settings.** No account, characters, bots, houses or auction
  history are included. The server creates your account the first time you click ENTER REALM,
  and you create bots from the launcher buttons. GM is off and XP is 1×.
- **The launcher names your edition:** VERSION 0.35b or VERSION 0.35.
- **A fresh client settings profile** for 0.35, so it never picks up an older copy's settings.
- **Bundled .NET runtime.** Nothing needs installing except the Windows .NET Framework 3.5
  feature.
- **Bring your save.** The progress transfer tool moves your account, characters, items, money,
  houses and bots from 0.34 and 0.34b, and from every earlier version. See
  [TRANSFER-PROGRESS.md](TRANSFER-PROGRESS.md).

## Classic quests

- **448 classic quests** from 1.65 and classic Shrouded Isles (1,302 quest versions counting the
  per-class versions of the epic and trainer quests), from the original class epics to trainer,
  optional and kill-task quests, with their recorded dialogue and experience.
- Quest NPCs and monsters the server lacked are placed where the period walkthroughs put them.
  Kill-task monsters live in camps that bots grind too.
- Steps beyond talking and killing work: using an item at a place, reaching a place, trading a
  drop to an NPC, choosing a reward by whispering its name, speaking the words of power with /say,
  NPCs that are summoned for you and quest NPCs that turn on you.
- **Red map markers** for every quest in your journal, each with its own marker.
- **Quest Guide:** the Quest Journal's QUEST GUIDE button, /questguide, or /task with no guard,
  merchant or crafter targeted shows the Allakhazam walkthrough of your active quests as it read in
  2001-2004. The guides were written by Allakhazam's contributors and each one names its source.
- Quest rewards are still in progress: many reward items are not in yet.

## The world of the period

- Monster populations restored from period bestiaries across the classic and Shrouded Isles zones.
- All four battlegrounds have their monsters, and bots can take part in them.
- The realm war map shows the classic frontier with every keep in its place.
- Bots walk where players walk: the navigation maps of 63 outdoor zones were rebuilt, and zone
  crossings only happen where real ground meets.

## Raids, sieges and battlegrounds

- New neutral raid events for every realm: Summoner's Hall and Darkness Falls.
- Raids lead bosses back to their lair the way players do, and bosses that only took damage from
  players can now be hurt by bots.
- Keep and relic sieges: armies gather at their portal outposts, march as one column, set up rams,
  catapults, trebuchets and ballistas, and every side goes after a stolen relic.
- Your /raid 40 and /raid 80 fight keep sieges on their own, and attacking an enemy keep raises a
  defense sized to your force.
- A short line at the top of the screen announces sieges, relic captures and raid victories (each
  can be switched off in the launcher's Options).

## Gamebots and companions

- Gamebots use the town teleporters and stop beside teleporter NPCs instead of standing on them.
- Gamebots earn realm points and train realm abilities, and enemy gamebots show as their race, as
  enemy players did.
- Groups travel smoothly, pull from range and look ahead for aggressive monsters on their routes.
- Companion pets come along when you travel, and casters fight with their staff when out of power.

## Launcher

- Scales with Windows display scaling. New Options tab (announcement switches), Battlegrounds tab,
  Battlegrounds % bot goal, BOT AI DELAY readout and a DELETE ALL RECORDS button.
