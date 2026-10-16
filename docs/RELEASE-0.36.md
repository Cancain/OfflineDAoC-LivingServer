# Offline DAoC 0.36

0.36 continues from 0.35. It collects every fix and feature added since 0.35 in one complete download, and it adds
a second game client: **0.36c, the new client**. Every single change is listed in the [changelog](../CHANGELOG.md).

## Three editions

They are the same game on the same server. Only the client and the custom class differ:

| Edition | What it is |
|---|---|
| **0.36b** | The original DAoC client, with the custom Hibernian **Sluaghbinder** class for players and bots. |
| **0.36** | The original DAoC client with the classic Classic + Shrouded Isles class list only. |
| **0.36c** | 0.36b or 0.36 with **both** clients: the original one and the [new client](NEW-CLIENT.md). Both play the same account, characters, bots and world, so you can switch whenever you like. |

## Downloading and starting

- **One small downloader per edition.** From the release page, download `Download-OfflineDAoC-v0.36b.zip` (or
  `-v0.36` / `-v0.36c`), unzip it and double-click the `.cmd` inside. It fetches the game in parts, checks every
  part and unpacks one ready-to-play folder.
- **0.36c installs everything in one go:** it asks whether you want 0.36b (with the Sluaghbinder) or 0.36 (classic
  classes only), installs that complete game, then the new client, in the same folder. If you already have 0.36b or
  0.36, `ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd` adds the new client to it. On a 0.36 game the new client offers the
  classic classes only, exactly like the original client there.
- **Your own account, world and settings.** No account, characters, bots, houses or auction history are included.
  The server creates your account the first time you click ENTER REALM, and you create bots from the launcher
  buttons. GM is off and XP is 1x. Every keep, relic and battleground keep starts with its original owner.
- **The launcher names your edition:** VERSION 0.36b, VERSION 0.36, or VERSION 0.36c in the new client's launcher.
- **Bring your save.** The progress transfer tool moves your account, characters, items, money, houses and bots
  from 0.35 / 0.35b and every earlier version. See [TRANSFER-PROGRESS.md](TRANSFER-PROGRESS.md).

## The new client (0.36c)

- A new client for the same game, built in Godot 4: the original zones, models, spell effects, sounds and interface,
  converted from the game's own files with textures upscaled 4x.
- The 1.65-era interface with its windows, quickbars, maps, journal, group and raid windows, trainer, merchants and
  the Realm Exchange; WoW-style movement; graphics presets.
- Shares everything with the original client. See [NEW-CLIENT.md](NEW-CLIENT.md).

## Raids, sieges and battlegrounds

- Bot raids finished **Darkness Falls** (Legion defeated), **Summoner's Hall** and **Tuscaran Glacier**, and killed
  **Prince Ba'alorien**, **Soul Reckoner** and **Hurionthex** for the first time.
- Raids gather before the last boss, share cramped spots, pull a boss's helpers first and stop chasing bosses they
  have already killed. Bosses no longer heal to full mid-fight or stay immune outside their leash.
- The Darkness Falls bosses that stood on daises out of reach (Princess Nahemah, High Lord Saeor, High Lord Oro) now
  stand on the floor in front of them.
- Keep and relic armies gather longer, march together around enemy keeps, and start the siege when the army arrives.
  Rams and trebuchets attack a keep's doors in the right order.
- Battleground armies attack the central keep together; bots took a battleground keep for the first time.
- You can take an enemy relic with your companion bots: they count on the relic pad, and eight are needed now.

## Bots and the world

- Bots find hunting spots that can only be reached the long way around: the server keeps a map of checked paths
  through every outdoor zone (`navmesh\roads.json`), and the Hibernian dragon raid takes a much shorter way.
- Bots use town teleporters more reliably and step off small loose pieces of the walking map.
- Fixed a slow memory leak that made long sessions stutter, and dead pets no longer stay in memory.
- NPCs no longer stay invisible after a teleport.

## Quests

- Classic quests give their item rewards (940 reward items added) and much more experience, as on the live servers
  in 2002-2004.
- Every classic quest can be finished from start to finish; quest NPCs hold their recorded conversations step by
  step; epic quests answer whispers again.
- Quest kill targets come back within five minutes.

## Classes

- Necromancer and Bonedancer pets look as they did in 1.65.
- The Sluaghbinder has realm abilities, including its own Crippling Plague (0.36b, and 0.36c with 0.36b).
