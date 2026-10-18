"""Make the small downloader zips the 0.37 release pages offer, and add them to each release's SHA256SUMS.txt.

    python make_downloaders_037.py --repo <this repository> --assets <assets folder with v0.37b, v0.37, v0.37c>

Each zip holds Get-OfflineDAoC.ps1, the edition's .cmd file and a short READ ME, in one folder:
  Download-OfflineDAoC-v0.37b.zip   GET-OFFLINE-DAOC-v0.37b.cmd
  Download-OfflineDAoC-v0.37.zip    GET-OFFLINE-DAOC-v0.37.cmd
  Download-OfflineDAoC-v0.37c.zip   GET-OFFLINE-DAOC-v0.37c.cmd
Each .cmd asks one question: 1 = update the game you have (0.36 / 0.36b / 0.36c), 2 = new install.
"""
from __future__ import annotations

import argparse
import hashlib
import zipfile
from pathlib import Path

EDITIONS = {
    "0.37b": ("GET-OFFLINE-DAOC-v0.37b.cmd",),
    "0.37": ("GET-OFFLINE-DAOC-v0.37.cmd",),
    "0.37c": ("GET-OFFLINE-DAOC-v0.37c.cmd",),
}
UPDATE = ("  1 = Update my game: you already have Offline DAoC 0.36, 0.36b or 0.36c. Choose your game\r\n"
          "      folder; only the update is downloaded, and your account, characters, bots and settings stay.\r\n")
README = {
    "0.37b": "Double-click GET-OFFLINE-DAOC-v0.37b.cmd (Offline DAoC 0.37b, with the custom Sluaghbinder class)\r\n"
             "and press 1 or 2:\r\n" + UPDATE +
             "  2 = New install: the complete game into a new folder next to it, playable-v0.37b.",
    "0.37": "Double-click GET-OFFLINE-DAOC-v0.37.cmd (Offline DAoC 0.37, the original Classic + Shrouded Isles\r\n"
            "classes only) and press 1 or 2:\r\n" + UPDATE +
            "  2 = New install: the complete game into a new folder next to it, playable-v0.37.",
    "0.37c": "Double-click GET-OFFLINE-DAOC-v0.37c.cmd (Offline DAoC 0.37c, BETA: the original client and the new\r\n"
             "client) and press 1 or 2:\r\n" + UPDATE +
             "      If your game doesn't have the new client yet, it asks whether to add it.\r\n"
             "  2 = New install: it asks for 0.37 or 0.37b, then installs the complete game and the new client in a\r\n"
             "      new folder next to it.",
}
FOOTER = ("\r\n\r\nKeep this folder's path short (for example C:\\Games\\OfflineDAoC). If Windows asks whether to run the\r\n"
          "file, choose Run (or More info -> Run anyway). If a download stops, run the same file again: it\r\n"
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
            raise SystemExit(f"{folder} has no download-manifest.json; make the patches first")
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
        sums = folder / "SHA256SUMS.txt"
        lines = [f"{sha(p)}  {p.name}" for p in sorted(folder.iterdir()) if p.is_file() and p.name != "SHA256SUMS.txt"]
        sums.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"{archive.name}: {archive.stat().st_size:,} bytes, {', '.join(cmds)}")


if __name__ == "__main__":
    main()
