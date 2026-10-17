"""Make the small downloader zips the 0.36 release pages offer, and add them to each release's SHA256SUMS.txt.

    python make_downloaders_036.py --repo <this repository> --assets <assets folder with v0.36b, v0.36, v0.36c>

Each zip holds Get-OfflineDAoC.ps1, the edition's .cmd file(s) and a short READ ME, in one folder:
  Download-OfflineDAoC-v0.36b.zip   DOWNLOAD-AND-PLAY-v0.36b.cmd
  Download-OfflineDAoC-v0.36.zip    DOWNLOAD-AND-PLAY-v0.36.cmd
  Download-OfflineDAoC-v0.36c.zip   DOWNLOAD-AND-PLAY-v0.36c.cmd and ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd
"""
from __future__ import annotations

import argparse
import hashlib
import zipfile
from pathlib import Path

EDITIONS = {
    "0.36b": ("DOWNLOAD-AND-PLAY-v0.36b.cmd",),
    "0.36": ("DOWNLOAD-AND-PLAY-v0.36.cmd",),
    "0.36c": ("DOWNLOAD-AND-PLAY-v0.36c.cmd", "ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd"),
}
README = {
    "0.36b": "Double-click DOWNLOAD-AND-PLAY-v0.36b.cmd. It downloads Offline DAoC 0.36b (with the custom\r\n"
             "Sluaghbinder class) into a new folder next to it, playable-v0.36b.",
    "0.36": "Double-click DOWNLOAD-AND-PLAY-v0.36.cmd. It downloads Offline DAoC 0.36 (the original Classic +\r\n"
            "Shrouded Isles classes only) into a new folder next to it, playable-v0.36.",
    "0.36c": "New install: double-click DOWNLOAD-AND-PLAY-v0.36c.cmd. It asks whether you want the game with the\r\n"
             "Sluaghbinder (0.36b) or with the classic classes only (0.36), then downloads that game AND the new\r\n"
             "client into a new folder next to it.\r\n\r\n"
             "Already have Offline DAoC 0.36b or 0.36: double-click ADD-NEW-CLIENT-TO-0.36-OR-0.36b.cmd and choose\r\n"
             "your game folder. The new client is added; your saves are not changed.",
}
FOOTER = ("\r\n\r\nKeep this folder's path short (for example C:\\Games\\OfflineDAoC). If Windows asks whether to run the\r\n"
          "file, choose Run (or More info -> Run anyway). If the download stops, run the same file again: it\r\n"
          "continues where it stopped. Full guide: https://github.com/shadowofze/OfflineDAoC/blob/main/docs/PLAY.md\r\n")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--only", nargs="+", choices=list(EDITIONS), help="remake only these editions' downloaders")
    args = parser.parse_args()
    repo, assets = args.repo.resolve(), args.assets.resolve()
    for version, cmds in EDITIONS.items():
        if args.only and version not in args.only:
            continue
        folder = assets / f"v{version}"
        if not (folder / "download-manifest.json").is_file():
            raise SystemExit(f"{folder} has no download-manifest.json; seal the release first")
        name = f"Download-OfflineDAoC-v{version}"
        archive = folder / f"{name}.zip"
        archive.unlink(missing_ok=True)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
            for file in ("Get-OfflineDAoC.ps1",) + cmds:
                data = (repo / file).read_bytes()
                if file.endswith(".cmd"):
                    assert b"\r\n" in data and b"\n" not in data.replace(b"\r\n", b""), f"{file} must use CRLF"
                zf.writestr(f"{name}/{file}", data)
            zf.writestr(f"{name}/READ ME.txt", (f"OFFLINE DAOC {version} - DOWNLOADER\r\n\r\n" + README[version] + FOOTER).encode("ascii"))
        with zipfile.ZipFile(archive) as zf:
            assert zf.testzip() is None
        # SHA256SUMS lists every asset of the release (the joined archive line of v0.36b is kept)
        sums = folder / "SHA256SUMS.txt"
        keep = [line for line in sums.read_text(encoding="utf-8").splitlines() if "(joined parts)" in line] if sums.exists() else []
        lines = [f"{sha(p)}  {p.name}" for p in sorted(folder.iterdir()) if p.is_file() and p.name != "SHA256SUMS.txt"]
        sums.write_text("\n".join(lines + keep) + "\n", encoding="utf-8")
        print(f"{archive.name}: {archive.stat().st_size:,} bytes, {', '.join(cmds)}")


if __name__ == "__main__":
    main()
