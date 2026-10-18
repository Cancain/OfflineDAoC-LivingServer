# Older versions

Every earlier Offline DAoC release is still available and unchanged. The easiest way to get one is
from its release page. Download that release's own `.cmd` helper and `Get-OfflineDAoC.ps1` into a
new folder and run the helper:

| Version | Release page | Helper |
|---|---|---|
| 0.36 (classic classes only) | [v0.36](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36) | `DOWNLOAD-AND-PLAY-v0.36.cmd` |
| 0.36b with Sluaghbinder | [v0.36b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36b) | `DOWNLOAD-AND-PLAY-v0.36b.cmd` |
| 0.36c, both clients | [v0.36c](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.36c) | `DOWNLOAD-AND-PLAY-v0.36c.cmd`, `ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd` |
| 0.35 "Claude Takeover III" | [v0.35](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.35) | `DOWNLOAD-AND-PLAY-v0.35.cmd` |
| 0.35b with Sluaghbinder | [v0.35b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.35b) | `DOWNLOAD-AND-PLAY-v0.35b.cmd` |
| 0.34 "Claude Takeover II" | [v0.34](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.34) | `DOWNLOAD-AND-PLAY-v0.34.cmd` |
| 0.34b with Sluaghbinder | [v0.34b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.34b) | `DOWNLOAD-AND-PLAY-v0.34b.cmd` |
| 0.33 "Claude Takeover" | [v0.33](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.33) | `DOWNLOAD-AND-PLAY-v0.33.cmd` |
| 0.33b with Sluaghbinder | [v0.33b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.33b) | `DOWNLOAD-AND-PLAY-v0.33b.cmd` |
| 0.32 Darkness Falls beta | [v0.32](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.32) | `DOWNLOAD-AND-PLAY-v0.32.cmd` |
| 0.32b with Sluaghbinder | [v0.32b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.32b) | `DOWNLOAD-AND-PLAY-v0.32b.cmd` |
| 0.31 / 0.31b | [v0.31](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.31), [v0.31b](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.31b) | `DOWNLOAD AND PLAY.cmd`, `DOWNLOAD AND PLAY v0.31b.cmd` |
| 0.3 | [v0.3](https://github.com/shadowofze/OfflineDAoC/releases/tag/v0.3) | `DOWNLOAD AND PLAY v0.3.cmd` |

The helpers in this folder do the same thing when run from a clone of this repository. They use
the shared `Get-OfflineDAoC.ps1` in the folder above, which still supports every version.

Their source is on the release branches (`release/v0.31-maintenance`, `release/v0.31b-sluaghbinder`,
`release/v0.32-darkness-falls`, `release/v0.32b-sluaghbinder-darkness-falls`,
`release/v0.33-claude-takeover`, `release/v0.34-claude-takeover-ii`,
`release/v0.35-claude-takeover-iii`, `release/v0.36`) and tags, and their
notes are in [docs/history](../docs/history/).

0.36 / 0.36b / 0.36c are also the base the 0.37 updates apply to. To move a save from any older version into 0.37 (or 0.37b / 0.37c), see [TRANSFER-PROGRESS.md](../docs/TRANSFER-PROGRESS.md).
