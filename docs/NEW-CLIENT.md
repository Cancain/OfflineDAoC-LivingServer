# The new client (0.36c)

0.36c adds a second game client to Offline DAoC 0.36b or 0.36: a new client built in the Godot 4 engine. It plays
the same game as the original client. It connects to the same local server, logs in with the same account, and
shows the same characters, bots, items and world.

You can switch between the two clients whenever you like. A character you play with the original client today
is the same character with the new client tomorrow.

## What it is

- **The same game.** The new client is only a client. Every rule, monster, quest, item and bot comes from the
  same Offline DAoC server as 0.36b and 0.36.
- **The game's own art, redrawn by a modern engine.** The zones, buildings, characters, monsters, spell effects,
  sounds, music and interface are converted from the original game client's own files, with textures upscaled
  4x.
- **The 1.65-era interface:** the original windows, quickbars, map and war map, quest journal, group and raid
  windows, pet window, trainer, merchants, the Realm Exchange, keybinds (mouse buttons too) and options,
  including graphics presets.
- **WoW-style movement:** hold the right mouse button to steer, A/D to turn, Q/E to strafe.

## Installing it

Everything happens in one folder. The new client lives in `new-client\` inside a 0.36b or 0.36 game folder:

```
playable-v0.36c\
  START OFFLINE DAOC.cmd               the original client
  START OFFLINE DAOC - NEW CLIENT.cmd  the new client
  runtime\                             the server, the world and YOUR SAVES (shared by both)
  new-client\                          the new client and its own settings
```

- **New install:** from the [v0.36c release](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36c),
  download `Download-OfflineDAoC-v0.36c.zip`, unzip it, and double-click `DOWNLOAD-AND-PLAY-v0.36c.cmd`. It
  asks which game you want (press **1** for 0.36b with the Sluaghbinder, **2** for 0.36 with the classic classes
  only), installs that complete game and then the new client.
- **Already have 0.36b or 0.36:** from the same downloader zip, double-click `ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd`
  and choose your game folder (the one with `START OFFLINE DAOC.cmd` in it). Nothing in that folder is changed except that the
  new client is added.

The download is large (about 30 GB, in 19 checked parts). The helper checks every part, unpacks it and deletes it
before fetching the next, and it continues where it stopped if you run it again. Keep the game folder's path
short (for example `C:\Games\OfflineDAoC`); the helper tells you if it is too long.

The new client works with both editions. On **0.36b** it offers every class, the Sluaghbinder too. On **0.36**
(classic classes only) it offers the classic classes only, exactly like the original client there: its launcher
reads the game's class setting and tells the new client.

## Playing

1. Double-click **START OFFLINE DAOC - NEW CLIENT.cmd**. The launcher opens (it shows VERSION 0.36c).
2. Click **START SERVER** and wait for **RUNNING**.
3. Click **ENTER REALM**. The new client starts and logs you in with your account.

Use **one launcher at a time**: both launchers start and stop the same server. To change clients, quit the
game, click STOP SERVER, close the launcher and open the other start file.

## Requirements

- Everything the 0.36b or 0.36 game needs (see [PLAY.md](PLAY.md)). The new client itself does not need the .NET
  Framework 3.5 feature; the original client does.
- A graphics card that supports **Vulkan or DirectX 12** (most cards from the last ten years), with up-to-date
  drivers.
- About 60 GB of free disk space while installing (the game plus the new client); about 45 GB afterwards.
- 16 GB RAM or more is recommended: the server, its bots and the client all run on your PC.

## Where things are

| What | Where |
|---|---|
| Your account, characters, bots, world | `runtime\data` (shared by both clients) |
| The new client's settings, keybinds, quickbars, logs | `new-client\save` |
| The new client's launcher | `new-client\runtime` (it runs the server in `runtime`, named in `server_root.txt`) |
| The new client | `new-client\godot` (code and converted content), `new-client\tools\godot_net` (the engine) |

## Bringing progress from an older version

Use **IMPORT PROGRESS FROM OLD OFFLINE DAOC.cmd** in the game folder, as in 0.36b and 0.36. The progress goes into
`runtime\data`, so both clients have it.

## Reporting problems

The new client is new. If something looks or behaves differently from the original client, please report it
in **[Bug reports](https://github.com/shadowofze/OfflineDAoC/discussions/14)** on the GitHub page, with a screenshot if you can, and say that it is the new client.

## For developers

The new client's source code is in [source/new-client](../source/new-client) (the Godot project and the Python
content pipeline that converts the original client's files). See its README. The converted content itself is
not in the repository; it comes with the 0.36c download.
