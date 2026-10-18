# How to download and play

You don't need Git, programming knowledge or an AI tool to play.

## Before you start

**What you need:**
- A 64-bit Windows 10 or 11 PC whose CPU supports **AVX2**. Most CPUs from 2014 onward do.
- 16 GB RAM is recommended; 8 GB may work but is untested.
- About **20 GB of free disk space** for 0.36b or 0.36 (5 GB of downloads, 5 GB while they are unpacked, 8 GB for the game, and room for saves), and about **60 GB** while 0.36c installs. The downloads can be deleted afterwards (the `.downloads` folder next to the helper).
- For the new client (0.36c): a graphics card that supports **Vulkan or DirectX 12**, with up-to-date drivers.

**Turn on the Windows .NET Framework 3.5 feature.** The original game client's connector needs it,
even though the game bundles its own modern .NET. (The new client of 0.36c doesn't need it.)
1. Open the Start menu and type **Turn Windows features on or off**, then open it.
2. Tick **.NET Framework 3.5 (includes .NET 2.0 and 3.0)**.
3. Click **OK** and let Windows download and install it.
4. Restart the PC if Windows asks.

If the game window never appears after ENTER REALM, this feature is the usual cause.

## 1. Pick an edition

| Edition | Choose it if… |
|---|---|
| **0.36b** | You want the custom Hibernian **Sluaghbinder** class, for you and the bots. |
| **0.36** (recommended) | You want only the original Classic + Shrouded Isles classes. |
| **0.36c** (BETA) | You want **both** game clients: the original one and the [new client](NEW-CLIENT.md). They play the same account, characters and bots. The installer asks whether you want it with 0.36b (with the Sluaghbinder) or 0.36 (classic classes only). |

**If you're unsure, pick 0.36.** It is the game as it was, with the original Classic + Shrouded Isles classes.
0.36b is the same game plus one custom Hibernian class, the Sluaghbinder, for you and the bots.

**Want to try the new client?** 0.36c is in beta. It gives you the new client *and* the original client in one
folder, playing the same account, characters, bots and world. Start either one from its own start file, and swap
between them whenever you like. If the new client isn't for you, just keep playing with the original client: nothing
is lost. You can also add the new client to a 0.36 or 0.36b game later (see below).

## 2. Download

1. Make a new, empty folder with a short path, for example `C:\Games\OfflineDAoC`.
2. From your edition's release page, download the one downloader zip into that folder:
   - [v0.36b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36b): `Download-OfflineDAoC-v0.36b.zip`
   - [v0.36](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36): `Download-OfflineDAoC-v0.36.zip`
   - [v0.36c](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36c): `Download-OfflineDAoC-v0.36c.zip`
3. Right-click the zip and choose **Extract All…**, then open the extracted folder.
4. Double-click the `DOWNLOAD-AND-PLAY-….cmd` file. If Windows asks whether to run it, choose **Run** (or
   **More info → Run anyway**).

The helper:
1. downloads the game in parts (0.36b and 0.36: about 5 GB; 0.36c: about 5 GB plus about 30 GB for the new client)
2. checks each part against its published fingerprint (SHA-256)
3. unpacks the game into a new folder next to the helper (`playable-v0.36b`, `playable-v0.36`, or for 0.36c
   `playable-v0.36c` / `playable-v0.36c-classic`)

It never overwrites an existing game and never starts anything by itself. If a download is
interrupted, run the helper again: finished parts are kept and only the missing ones are fetched.

**Already have 0.36b or 0.36 and want the new client?** In the 0.36c downloader zip, double-click
`ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd` and choose your game folder. See [NEW-CLIENT.md](NEW-CLIENT.md).

## 3. Play

1. Open the new `playable-…` folder and double-click **START OFFLINE DAOC.cmd** (in 0.36c, or
   **START OFFLINE DAOC - NEW CLIENT.cmd** to play with the new client).
2. In the launcher, click **START SERVER** and wait until it shows **RUNNING**. The first start
   takes longer.
3. Click **ENTER REALM**. The first time, your own local account is created automatically.
4. Create your character and play.
5. When you're done, quit the game, then click **STOP SERVER** in the launcher and wait for it to
   finish saving.

### Bots

A new install starts with an empty world:
1. Each realm's card in the launcher (**ALBION**, **MIDGARD**, **HIBERNIA**) has buttons to create
   level 1 or level 50 gamebots, 1, 10 or 100 at a time.
2. New bots log in gradually and then play on their own.

The launcher's bot goals settings choose how much bots solo, group or go to RvR at each level
range. You can recruit companion bots in game.

#### How many bots?

Counts are gamebots per realm (Albion / Midgard / Hibernia):

| Bots per realm | Experience |
|---|---|
| **500 / 500 / 500** or fewer | Low population. |
| **1000 / 1000 / 1000** | Regular populated server. Enough level 50 bots to complete all content, and a living world. Going above this may cause server lag or database locks more often. |
| **1500 / 1500 / 1500** | High population. |
| **2000 / 2000 / 2000** | Full server. |
| More than 2000 per realm | Likely impractical. |

With a lot of load, bots may also move more slowly.

There is a hard ceiling from bot name generation. Each realm has its own male and female name
pools, 20,414 unique names in total:
- Albion has 7,496.
- Midgard has 6,494.
- Hibernia has 6,424.

The launcher picks each bot's gender at random. A realm's batch fails once that realm's smaller
pool is used up, so creation stops at about:
- **6,900 Albion**, **5,700 Midgard** and **6,200 Hibernia** bots;
- **about 18,800 in total**.

That means 6000 / 6000 / 6000 isn't reachable, because Midgard runs out first. It wouldn't be
practical anyway.

Handy in-game commands are listed in [QUICK-COMMANDS.md](QUICK-COMMANDS.md). The complete list is
in `ALL SERVER COMMANDS.txt`.

## Moving from an older version

Your old game keeps working and isn't changed. To bring your progress (account, characters, items,
money, houses and bots) into 0.36, follow [TRANSFER-PROGRESS.md](TRANSFER-PROGRESS.md).
In short:
1. Stop both games.
2. Run **IMPORT PROGRESS FROM OLD OFFLINE DAOC.cmd** in the new folder.
3. Pick your old folder.

## Troubleshooting

| Problem | Try this |
|---|---|
| The helper says the destination already exists | Delete or rename the old `playable-…` folder, or run the helper from a different empty folder. Existing games are never overwritten. |
| A part fails its check | Run the helper again; it downloads only what's missing or broken. |
| ENTER REALM stays greyed out | Wait until the launcher shows RUNNING. The first start can take a few minutes. |
| The game window doesn't appear | Turn on the .NET Framework 3.5 feature (see above), then try again. |
| "Port 10300 is in use" or the server won't start | Another Offline DAoC server is running. Stop it first; only one can run at a time. |
| Windows SmartScreen blocks a file | Choose **More info → Run anyway**. The files are unsigned community builds. |
| The new client says the folder path is too long | Move the game to a shorter path, for example `C:\Games\OfflineDAoC`, and run the helper again. |
| The new client's window stays black or closes at once | Update your graphics driver; the new client needs Vulkan or DirectX 12. |
| Two launchers are open | Use one at a time: both start and stop the same server. Close one before you start the server. |

## Older versions

Every earlier release (v0.3 to v0.35b) is still on the
[Releases page](https://github.com/shadowofze/OfflineDAoC/releases). Their helpers are in the
repository's [older-versions](../older-versions/) folder.
