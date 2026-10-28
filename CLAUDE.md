@AGENTS.md

## Rules for this fork

These apply on top of AGENTS.md (upstream's file, left untouched so merges stay easy).

- **Never change the game copy.** `D:\OfflineDAOC\Download-OfflineDAoC-v0.37\playable-v0.37`
  may only be read and copied from: never changed, started or written to. Test only in the
  dev copy `D:\OfflineDAOC\dev-v0.37`.
- **One server at a time.** Check that the game server is stopped (the launcher shows
  SERVER: STOPPED and no `CoreServer` processes are running) before starting the dev server.
- **One branch per idea.** Small, self-contained changes.
- **Install into the dev copy with a backup**, the same way as `tools/fork-build/install-server-build.ps1`:
  everything closed, a backup of every file replaced, every copy verified by SHA-256.
- **Talk to the user and write RAPPORT.md in Swedish.**
- **Everything committed to the repo is in English:** code comments, commit messages, branch
  names, PR titles and descriptions, docs.
- **No AI attribution.** Never add Co-Authored-By lines or other AI attribution to commit
  messages or PR descriptions.
