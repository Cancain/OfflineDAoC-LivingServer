# Audit and release plan (2026-10-12)

What was built on Chris's fork (`chris4aker/OfflineDAoC`) on 2026-10-11 and 2026-10-12, what state
each piece is in, and the plan to code, test, install and release it.

**New development stops here** until this release is played and fixed.

## 1. Audit

### 1.1 Base

| Fact | Status |
|---|---|
| Fork `main` is `d121209`. Its `source/` is identical to the **v0.35 / v0.35b** release tag (`d337d18`). | verified (git diff) |
| shadowofze's newest commits (to `1cabc77`) are **changelog text only**. The 0.36 code (DXVK client, quest rewards, DF raid fix) is "local, not released yet" and isn't in the repo. | verified |
| A server built from our branches therefore matches a **v0.35 or v0.35b install**. 0.35 and 0.35b share one server build; the edition is a database setting. | verified (same tag, same source) |

### 1.2 Workstreams

| Workstream | Branch | What exists | Automated tests | In game | In this release? |
|---|---|---|---|---|---|
| XP rate by level range | `feature/xp-by-level-range` | Code, helper script `set_xp_by_level.py`, release and transfer clean-up, doc | Green | **Not tested** | Yes, off until set |
| Bot guilds, phases 1–6 | `feature/bot-guilds` | Formation, chat, recruiting you, grouping, keep claims and defense, dues, merit, buffs, alliances; helper `set_bot_guilds.py`; doc | Green (95 tests) | **Not tested** | Yes, off until turned on |
| Bot voices | `feature/bot-voices` | Research brief, design, corpus (842 lines, 296 scenes), build and preview tools. **No game code.** | Corpus checker passes | n/a | Data only; no effect (not embedded in the build) |
| Living-world planning | `living-world/trade-sim` | Roadmap, audit, data check, Kirstena's Atlas check, trade, persona and RvR simulators | n/a | n/a | No (planning) |
| CI (GitHub Actions, Windows) | on every branch | Build, launcher, full server tests, feature test counts | n/a | n/a | Yes (tooling) |

### 1.3 Combined check (verified 2026-10-12)

- **Merge:** the three feature branches merge onto `main` as `integration/next`. The only conflict
  is the CI workflow file, which each branch added; it's resolved there.
- **CI on the combined code:** **2,769 of 2,769** server tests pass, 142 of them for these features
  (run 38264451720).
- **Release clean-up:** run on a copy of the 0.35 world database seeded with played state from
  both features: bot guilds, alliances, keep claims, guild bank and merit, the bot guild settings
  and both XP settings. All were cleared, and the builder's own verification passed.
- **Bot-voices corpus:** not embedded (the server project lists embedded files one by one). It
  doesn't change the build.

### 1.4 Findings to fix before release

| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | No downloadable server build. CI compiles and tests but publishes no `GameServer.dll`, and your PC has no build tools yet. | blocks release | CI **package** job: a zip with the Windows `GameServer.dll`, an install script and a rollback script |
| 2 | No safe install path. AGENTS.md requires deploying only tested output, with a backup, to `runtime/server`, `runtime/server/lib` and `runtime/server/win-x64`. | blocks release | `install-server-build.ps1`: refuses while the server, launcher or game runs; checks it's a 0.35/0.35b install; backs up all three copies; copies and verifies hashes. `rollback-server-build.ps1` restores the backup. |
| 3 | No way to tell which build is running. | medium | The server logs one line at startup: build name, git commit, and which features are switched on |
| 4 | Bot guild formation runs on a background timer thread, not the game loop. It creates guilds and their ranks there. It's the same pattern as phase 1 used, and low risk, but it's the one threading shortcut in the new code. | low | Move guild creation onto the game loop (as alliances already are) |
| 5 | Nothing has been played. Every result so far is an automated test. | — | Stages 3–5 below |
| 6 | Stale branches: `living-world/roadmap` and `ci/github-actions`. Everything in them exists in newer form elsewhere (verified). | housekeeping | Delete, with your OK |

## 2. Plan

Each stage ends with a check. Nothing moves on until the check passes.

### Stage 1: package and safety tooling (Claude, from here)

1. **Release branch:** turn `integration/next` into `release/0.35-chris.1`.
2. **Fixes:** findings 3 and 4 above.
3. **Package and install tooling:** the CI package job and the install/rollback scripts (findings 1 and 2).
4. **Run CI.**
   - **Automated checks:** full tests green; the zip artifact exists. The install script is
     checked against a fake install folder.
   - **Can't be tested here:** the real Windows install. That's stage 3.

### Stage 2: your PC (Chris, about an hour)

1. **Install the game:** download **Offline DAoC 0.35** (or 0.35b) from shadowofze's releases
   with the `DOWNLOAD-AND-PLAY` script.
2. **Play a baseline:** 30–60 minutes of the stock game, so you know what normal looks like:
   bots in towns and at camps, chat, a group.
3. **Optional:** open this chat in the Claude desktop app on that PC, so it's linked and Claude can
   read logs and run the install with you.

### Stage 3: install our build and smoke test (together)

1. Close the server, launcher and game.
2. Download the zip from the CI run (GitHub → Actions → the run → Artifacts).
3. Run `install-server-build.ps1`. It backs up first.
4. Start the server as usual and log in.
5. **Pass when:**
   - the startup line shows `0.35-chris.1` with every feature off;
   - there are no new errors in the log;
   - the game plays exactly like the baseline.
6. **On a failure:** run `rollback-server-build.ps1`, then send Claude the log.

### Stage 4: XP by level range

1. **Set the plan's rates:** with the server closed, run
   `python tools\claude-version\set_xp_by_level.py --player "1-19:3;20-34:5;35-50:12" --bots "1-19:1.5;20-34:2.5;35-50:6" --apply`.
   This is the goal from the roadmap's model v4: keep levels 1–34 worth playing, and compress the
   35–50 grind.
2. **Check in game:**
   - At about level 10, kill a few blue or yellow monsters: the XP should be about 3× the baseline.
   - On a character in the 20s it should be about 5×.
   - Above 35 (a /level GM character is fine) it should be about 12×.
3. **Turn it off** with `--off --apply`.
4. **Pass when** the numbers match.

### Stage 5: bot guilds

1. **Turn on:** with the server closed, run
   `python tools\claude-version\set_bot_guilds.py --on --apply`, start, and wait 10 minutes.
2. **Work through the checklist** in `docs/BOT-GUILDS.md` §4 in order:
   1. guild names over bots;
   2. "lf guild" → dialog → join;
   3. `/gu` replies, greetings and congratulations;
   4. 30 minutes of guild chat;
   5. `/gc info` bank and merit;
   6. a keep claim;
   7. alliance chat;
   8. `/ginvite` and `/gc remove` on a bot.
3. **Watch for:** chat floods, lag, or bots stuck forming groups.
4. **If one part misbehaves,** switch just that part off (for example `--claims off`) and note it.
5. **Pass when** the checklist is complete with no blocking problem.

### Stage 6: fix round

1. **Fix:** each problem found is fixed on its feature branch, then merged into the release
   branch.
2. **Build:** CI builds a new zip (`0.35-chris.2`, …).
3. **Retest** only the affected checklist items.
4. **Repeat** until stages 3–5 pass.

### Stage 7: release

1. **Merge:** pull request `release/0.35-chris.N` → `main`, with your approval.
2. **Tag:** `v0.35-chris.N` on your fork.
3. **Publish:** a GitHub Release with the zip, with your approval.
   - **Choice:** your fork is public, so the release would be too; a draft release keeps it to you.
   - **Contents:** only the server build (built from the GPL source) and the scripts; never a
     database, account, logs or rosters.
4. **Changelog** entry in the fork.

### Stage 8: keeping up with shadowofze

**When 0.36 code is published:**
1. Merge it into `main`.
2. Rebuild the release branch and rerun CI.
3. Repeat stage 3's smoke test on a 0.36 install, then release `0.36-chris.1`.

**Don't** install our 0.35-based build over a 0.36 install: it would roll back his 0.36 server
changes.

**Optional:** a weekly scheduled check for new shadowofze commits.

### After the release: the next coding project

**Bot voices, step 2:** load the corpus in the server, with voices, line choice and settings, then
test it in game the same way. After that come memory (step 3) and the living-world population
work (M1).

## 3. Decisions needed from Chris

1. **Go** for stage 1 (packaging and safety tooling).
2. **Delete** the two stale branches (`living-world/roadmap`, `ci/github-actions`).
3. **Release visibility** at stage 7: public release, or a draft for yourself only.
