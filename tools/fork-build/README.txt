OFFLINE DAOC - FORK SERVER BUILD (chris4aker/OfflineDAoC)
=========================================================

This is a server-only build for Offline DAoC 0.35 / 0.35b. It replaces GameServer.dll and adds
two features, both OFF until you switch them on:

  - XP rate by level range ........ docs\XP-BY-LEVEL-RANGE.md
  - Bot guilds .................... docs\BOT-GUILDS.md

With both off, the game should play exactly like the normal 0.35.

INSTALL
-------
1. Close the server, the launcher and the game.
2. Put this folder INSIDE your Offline DAoC game folder (the folder with START OFFLINE DAOC.cmd).
3. Double-click INSTALL.cmd. If Windows warns about an unknown app: More info -> Run anyway.

The installer checks that the game is 0.35 / 0.35b, refuses while anything is running, backs up
every file it replaces (runtime\server\deployment-backups\fork-build-<time>) and checks every
copy. It also puts two settings helpers in tools\claude-version and these docs in
docs\fork-build-<name>.

Check: start the game as usual. The server log shows a line like
  FORK_BUILD name=0.35-chris.1 commit=... bot_guilds=off xp_rate_by_level=off

UNDO
----
Close everything and double-click ROLLBACK.cmd. It puts back exactly the files the install
replaced.

SWITCHING FEATURES ON (server closed; needs Python 3)
---------------------------------------------------
  python tools\claude-version\set_xp_by_level.py --player "1-20:3" --apply
  python tools\claude-version\set_xp_by_level.py --off --apply
  python tools\claude-version\set_bot_guilds.py --on --apply
  python tools\claude-version\set_bot_guilds.py --off --apply

Without --apply they only show what they would change. Both back up the database first.

DON'T install this build on Offline DAoC 0.36 or later: it would undo that release's server
changes. The installer refuses it.

BUILD-INFO.txt names the build, the git commit and the SHA-256 of the files.
