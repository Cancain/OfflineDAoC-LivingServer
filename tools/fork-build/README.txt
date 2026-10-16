OFFLINE DAOC - FORK SERVER BUILD (chris4aker/OfflineDAoC)
=========================================================

This is a server-only build for Offline DAoC 0.36 / 0.36b, the "Social Expansion". It replaces
GameServer.dll and adds these features, all OFF until you switch them on:

  - XP rate by level range ........ docs\XP-BY-LEVEL-RANGE.md
    (the plan's values keep levels 1-34 worth playing and compress the 35-50 grind:
     you 3x / 5x / 12x, bots 1.5x / 2.5x / 6x for levels 1-19 / 20-34 / 35-50)
  - Bot guilds .................... docs\BOT-GUILDS.md
  - Bot personalities, voices
    and debates ................... docs\BOT-PERSONALITIES.md

With all of them off, the game should play exactly like the normal 0.36.

NEW CLIENT (0.36c): the new client runs the same server, so this build applies to it too.
It has not been tested with the new client yet; test with the original client first.

INSTALL
-------
1. Close the server, the launcher and the game.
2. Put this folder INSIDE your Offline DAoC game folder (the folder with START OFFLINE DAOC.cmd).
3. Double-click INSTALL.cmd. If Windows warns about an unknown app: More info -> Run anyway.

The installer checks that the game is 0.36 / 0.36b (with or without the 0.36c new client), refuses while anything is running, backs up
every file it replaces (runtime\server\deployment-backups\fork-build-<time>) and checks every
copy. It also puts three settings helpers in tools\claude-version and these docs in
docs\fork-build-<name>.

Check: start the game as usual. The server log shows a line like
  FORK_BUILD name=0.36-chris.1 commit=... bot_guilds=off xp_rate_by_level=off ... bot_personalities=off bot_voices=off

UNDO
----
Close everything and double-click ROLLBACK.cmd. It puts back exactly the files the install
replaced.

SWITCHING FEATURES ON (server closed; needs Python 3)
---------------------------------------------------
  python tools\claude-version\set_xp_by_level.py --player "1-19:3;20-34:5;35-50:12" --bots "1-19:1.5;20-34:2.5;35-50:6" --apply
  python tools\claude-version\set_xp_by_level.py --off --apply
  python tools\claude-version\set_bot_guilds.py --on --apply
  python tools\claude-version\set_bot_guilds.py --off --apply
  python tools\claude-version\set_bot_social.py --all on --apply
  python tools\claude-version\set_bot_social.py --all off --apply

Without --apply they only show what they would change. All of them back up the database first.

DON'T install this build on any other release (0.35 or older, or 0.37 or later): it would
change that release's server. The installer refuses it.

BUILD-INFO.txt names the build, the git commit and the SHA-256 of the files.
