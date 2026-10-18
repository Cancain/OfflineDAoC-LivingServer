# Offline DAoC 0.37

0.37 continues from 0.36 and is the first version that comes as an **update**: if you play 0.36, 0.36b or 0.36c, you
download only what changed and keep your account, characters, bots and settings. Every single change is listed in
the [changelog](../CHANGELOG.md).

## Three editions

They are the same game on the same server. Only the client and the custom class differ:

| Edition | What it is |
|---|---|
| **0.37** (recommended) | The original DAoC client with the classic Classic + Shrouded Isles class list only. |
| **0.37b** | The original DAoC client, with the custom Hibernian **Sluaghbinder** class for players and bots. |
| **0.37c** (BETA) | 0.37 or 0.37b with **both** clients: the original one and the [new client](NEW-CLIENT.md). Both play the same account, characters, bots and world. |

## Updating and installing

- **One downloader per edition, with one question.** From the release page, download `Download-OfflineDAoC-v0.37.zip`
  (or `-v0.37b` / `-v0.37c`), unzip it and double-click the `GET-OFFLINE-DAOC-….cmd` inside. Press **1** to update
  the game you have, or **2** for a new install.
- **Updating** finds out by itself which edition you have and whether it has the new client, checks that every file
  it replaces is as installed, backs everything up (in `patch-backups` in your game folder) and applies the update.
  World changes go into your database without touching your saves. If anything fails, it puts everything back.
- **If you changed game files** the update would replace, it lists them and changes nothing, and offers a fresh 0.37
  in a new folder with your progress brought over.
- **A new install** downloads the complete 0.36 game the update builds on, then updates it.
- **The launcher shows VERSION 0.37** (0.37b, 0.37c) once you are up to date.
- **Coming from 0.35 or older?** Install 0.37, then use the progress transfer tool. See
  [TRANSFER-PROGRESS.md](TRANSFER-PROGRESS.md).

## Guilds

- Form a guild on your own at a Guild Registrar (`/gc form <name>`), and invite your realm's gamebots into it
  (`/gc invite`). Guild bots show the guild name and wear its emblem on cloak and shield, and chat in guild chat.
- Your /spawn companions show your guild name and emblem while they are with you.

## Raids, sieges and battlegrounds

- Siege armies attack together, raise their fallen during the battle and, if they release, come back at their
  frontier muster point instead of their capital.
- Siege crews set up rams past the wrecks of broken engines; battleground assaults go through a broken main gate for
  the keep lord, and realms too small for an assault fight in the open field.
- Raids get further in Caer Sidi (the climb to the final encounter, the Skeletal Sacristan, Lich Lord Sanguis's blood
  mages) and Galladoria (the Earthmenders, the Watery Vortexes, the Organic-Energy Mechanism).
- Automatic raid rallies give their army time to arrive, and every dragon raid party can reach its spot round the
  lair.

## Bots and the world

- Bot groups travel as one pack, the way your companions follow you, and no longer freeze in front of a monster on
  the road.
- Bots take town teleporters only when it really is quicker, and those trips fail far less often.
- Bots step back onto real ground from cut-off patches at once, leave their portal keeps and the battlegrounds, and
  find a way across zone borders where the best-looking crossings lead into dead ends.
- 22 weapons, shields and armour pieces that were drawn as a bag now look like what they are.
- Far less lag on a busy server: fewer repeated route searches, and much less short-lived data, so memory clean-up
  pauses come less often.

## Quests

- Every classic quest can be started by talking to its giver: 20 quests had lost a line of their giver's
  conversation (Tale of Druids for every Albion class among them).
- Bounties count every monster with the bounty's name, at any level and anywhere.
- Quest markers update the moment you level up, and Fjall is back in the fenrir fort in Yggdra Forest.

## The new client (0.37c)

- Many fixes and additions: the release window's four choices, the trainer's specialization preview, combat style
  trails as in the original client, stable rides seated on the mount, monsters at their proper height, Half Ogre,
  Frostalf and Shar NPCs as their races, ground-target spells, fewer hitches when spell effects first appear, and more.
  See the changelog's new client section.
