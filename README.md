> **Disclaimer.** Dark Age of Camelot is the intellectual property of Electronic Arts and Broadsword
> Online Games. Offline DAoC is not affiliated with, endorsed by, or connected to either company. The
> game client, textures, models and other assets it uses belong to them, and this project is built on
> top of that copyrighted work.
>
> This is a free, non-commercial fan project. It is not a product and it is not for sale. No donations
> are accepted, and the project owner has not made, and will not make, any money from it. The client
> files are the same publicly available ones every free shard uses; the work original to this
> repository is the bot system and the server customizations. Because the code is open source, the
> owner cannot control what forks or other people do with it.
>
> This "time capsule" of the 2002-2003 game was never meant to compete with the current retail Dark Age
> of Camelot, which is a very different, modern experience. If that interests you, please visit the
> official site: [darkageofcamelot.com](https://www.darkageofcamelot.com/).

# Offline DAoC: Social Expansion

**Single-player Dark Age of Camelot that feels like a live 2003 server.** This fork of
[shadowofze's Offline DAoC](https://github.com/shadowofze/OfflineDAoC) gives its bots a social life.
They join guilds and recruit you, each has its own personality, and they talk the way players did in
2002–2003, down to the build arguments in /faction.

> **Status: in testing, not released yet.** The first release is planned for shadowofze's 0.36b once
> he publishes it. Watch this repository's [Releases](https://github.com/chris4aker/OfflineDAoC-SocialExpansion/releases).

## Why

Peak servers felt alive because of the people: the guild that adopted you at level 12, the officer
who called keep defense, the regular who said "ding" at the same camp every night, the endless
arguments over specs. Offline DAoC's bots already level, group, trade and fight on their own. The
Social Expansion makes them feel like a community, not just a population.

## What it adds

| Feature | What you'll see |
|---|---|
| **Bot guilds** | Each realm has its own bot guilds, a few big and many small, each with a purpose: leveling, social, RvR, raiding or crafting. Bots wear guild names, chat in /gu, group with guildmates, and recruit you when you ask "lf guild". Guilds claim and defend keeps, pay dues, earn merit, buy guild buffs and form alliances. You can also /ginvite bots into your own guild. |
| **Bot personalities** | Every bot is one of six types: Leveler, Socialite, Daredevil, Explorer, Crafter or No-lifer. Each also has five traits (curiosity, risk, sociability, patience, chattiness). Personality tilts how a bot spends its time: who lingers in town, who chases orange cons, who goes looking for zones they haven't seen. Target any bot and type `/personality`. |
| **Bot voices** | 842 lines written for the era and checked against period slang, chosen by realm, class, level, situation and personality. Each bot writes in one of five styles (plain, terse, chatty, proper or typo-prone). No line repeats in a realm within six hours. |
| **/faction debates** | 296 multi-bot conversations: class and spec arguments, relic and keep alerts, dragon raids, Darkness Falls, buffbots, zergs, realm pride and more. A different cast plays one every 30–45 minutes while you're online. |
| **XP by level range** | Separate player and bot XP rates for level bands. The suggested setting keeps levels 1–34 worth playing and compresses the 35–50 grind. |

## Safe to try

- **Everything starts switched off.** Turn each feature on with a one-line switch, and off again
  the same way. With all of them off, it plays exactly like the base game.
- **It never breaks the base game's rules.** Real loot, the Realm Exchange, stablemaster routes,
  bots earning their armor and the other owner rules are untouched.
- **Install and undo in one click.** The installer checks that your game is the right version,
  backs up every file it replaces, and verifies each copy. `ROLLBACK.cmd` puts the originals back.
- **It's tested.** 2,810 automated server tests pass on every build. In-game testing is underway.

## How to get it (once released)

1. Install the matching Offline DAoC from [shadowofze's releases](https://github.com/shadowofze/OfflineDAoC/releases).
2. Download the Social Expansion build from this repository's Releases and put its folder in your game folder.
3. Close the game and server, then double-click `INSTALL.cmd`.
4. Switch features on with the scripts in `tools\claude-version` (Python 3).

## Details

- [Bot guilds: design and status](https://github.com/chris4aker/OfflineDAoC-SocialExpansion/blob/release/0.35-chris.1/docs/BOT-GUILDS.md)
- [Bot personalities, voices and debates](https://github.com/chris4aker/OfflineDAoC-SocialExpansion/blob/release/0.35-chris.1/docs/BOT-PERSONALITIES.md)
- [XP by level range](https://github.com/chris4aker/OfflineDAoC-SocialExpansion/blob/release/0.35-chris.1/docs/XP-BY-LEVEL-RANGE.md)

## Credits

- **[shadowofze](https://github.com/shadowofze/OfflineDAoC)** made Offline DAoC: the bots, the world
  and everything this builds on. All of that work is his.
- **[OpenDAoC](https://github.com/OpenDAoC/OpenDAoC-Core)** is the open-source server underneath.
- **[stefanrows](https://github.com/stefanrows/OfflineDAoC)**: the core bot-guild membership code is
  adapted from his fork.
- The Social Expansion is directed by Chris
  ([chris4aker](https://github.com/chris4aker)) and written with Claude (Anthropic).

Same license as the original: GPL-3.0.

---

*Everything below is the original Offline DAoC README.*

# Offline DAoC — single-player Dark Age of Camelot with bots

Offline DAoC is a local, single-player Dark Age of Camelot (Classic + Shrouded Isles, 1.65 rules)
that runs entirely on your own PC. The world is filled with autonomous gamebots that level,
group, trade and fight on their own, and you can recruit companion bots to adventure with you.

It is a community project built on the open-source [OpenDAoC](https://github.com/OpenDAoC/OpenDAoC-Core)
server. The customizations were developed with AI tools (Codex, then Claude) and directed and
play-tested by the project owner. It is not an official DAoC product and is not for sale.

## Current release: 0.35 "Claude Takeover III"

0.35 carries on from 0.34 with 448 classic quests (red map markers and a period Quest Guide), the
monster populations of the period, Summoner's Hall and Darkness Falls raid events, keep and relic
sieges with siege engines, battlegrounds, the classic frontier war map, and smarter gamebots and
companions. Read [what's new in 0.35](docs/RELEASE-0.35.md), or every change in the [changelog](CHANGELOG.md).

There are two editions. They are the same game, and only the custom class differs:

| Edition | What it is | Download |
|---|---|---|
| **0.35b** (recommended) | Includes the custom Hibernian class, the **Sluaghbinder** (a pet-summoning undead binder), for players and bots. | [v0.35b release](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.35b) |
| **0.35** | The classic Classic + SI class list only. There are no Sluaghbinder players or bots. | [v0.35 release](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.35) |

## Download and play (no Git or AI needed)

1. **Requirements:**
   - A 64-bit Windows PC with a CPU that supports AVX2.
   - 16 GB RAM recommended.
   - About 20 GB of free disk space.
   - The Windows **.NET Framework 3.5** feature turned on. [How to turn it on](docs/PLAY.md#before-you-start).
2. **Download the helper:** from the release page of the edition you want, download two files into
   the same new, empty folder:
   - `DOWNLOAD-AND-PLAY-v0.35b.cmd` (or `-v0.35.cmd`)
   - `Get-OfflineDAoC.ps1`
3. **Run the helper:** double-click the `.cmd` file. It downloads the game (about 5 GB in parts),
   checks every part, and unpacks it into a new folder. It never overwrites an existing game.
4. **Start playing:** open the new folder and double-click **START OFFLINE DAOC.cmd**.
   1. Click **START SERVER** and wait until it says **RUNNING**.
   2. Click **ENTER REALM**.
   3. Your own local account is created automatically the first time.
5. **Create your bots:** use the bot buttons in the launcher. Every new install starts with an
   empty world and default settings.

The full walkthrough, with troubleshooting, is in [docs/PLAY.md](docs/PLAY.md).

> **Code > Download ZIP** on this page gives you the *source code*, not the playable game. Use the
> release helper above to get the game.

## Already playing an older version?

Your characters, account, items, money, houses **and bots** can come with you. The new version
includes **IMPORT PROGRESS FROM OLD OFFLINE DAOC.cmd**:
1. Close both games.
2. Run the import tool from the new folder.
3. Pick your old folder.

The tool never changes your old folder, and it backs up the new one first. It works with v0.3,
v0.31, v0.31b, v0.32, v0.32b, v0.33, v0.33b, v0.34, v0.34b and the "new class test" builds. See
[docs/TRANSFER-PROGRESS.md](docs/TRANSFER-PROGRESS.md).

## Older versions

Every earlier release is still available and unchanged:
- [v0.34](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.34) and
  [v0.34b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.34b): "Claude Takeover II".
- [v0.33](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.33) and
  [v0.33b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.33b): "Claude Takeover".
- [v0.32](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.32) and
  [v0.32b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.32b): Darkness Falls beta.
- [v0.31](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.31) and
  [v0.31b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.31b).
- [v0.3](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.3).

Their download helpers are in [older-versions/](older-versions/), and their notes are in
[docs/history/](docs/history/). Each release's source code stays on its own branch and tag (for
example `release/v0.33-claude-takeover` and `v0.33b`), so older code is always there to compare.

## For developers and AI assistants

- **Where to start:** [AGENTS.md](AGENTS.md) (also read by Claude as [CLAUDE.md](CLAUDE.md)) has
  the project rules.
- **Guides:** [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building and testing, and
  [docs/LLM-QUICKSTART.md](docs/LLM-QUICKSTART.md) covers customizing with your own AI.
- **Where the code is:**
  - `source/server`: the game server and all bot AI.
  - `source/tools`: the launcher and the progress importer.
  - `tools/pet-art`: the art pipeline used for the custom pets, weapons and spell effects.
- **Forking:** you don't need permission to fork this repository and make it your own. Keep the
  existing licenses and credits ([THIRD_PARTY.md](THIRD_PARTY.md)).

## Good to know

- **What the download includes:**
  - the full game client
  - clean world data and navigation meshes
  - the launcher and server
  - the progress import tool
  - the bundled .NET runtime
  - the source code

  It does **not** include anyone's account, characters, bots or settings. Every install makes its
  own.
- **Darkness Falls is still beta.** All three realms can enter, and bots grind its ordinary
  camps. Raid AI isn't implemented. Legion, the hardest level 70+ encounters, unreachable flying
  targets and unverified routes are left out of bot goals.
- **AI-written code can have bugs.** Keep a backup of your save before installing a new build or
  mod. There's no guarantee against regressions.
- **Licensing:** the original game client is a binary dependency. This repository has the server,
  tools and customization source, not the client's source code. The server's license doesn't
  relicense third-party client assets or dependencies. See [THIRD_PARTY.md](THIRD_PARTY.md).
- **Local only:** the default setup is for one PC. Running a public multiplayer server would need
  its own security work.

## Videos

[![Optional Hibernian Sluaghbinder class](https://i.ytimg.com/vi/EowrCcjigBY/hqdefault.jpg)](https://www.youtube.com/watch?v=EowrCcjigBY)
[![Raids and realm events](https://i.ytimg.com/vi/zmh7YkajRx0/hqdefault.jpg)](https://www.youtube.com/watch?v=zmh7YkajRx0)

## Changes

See the [changelog](CHANGELOG.md).
