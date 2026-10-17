"""Seal the 0.36c new client package into verified, independent release parts.

    python seal_newclient_036.py --package <staging>/OfflineDAoC-v0.36c --out <assets folder>

Writes new-client/PACKAGE MANIFEST.sha256, then packs the package into independent zip parts (each a complete zip below
GitHub's 2 GB limit, root folder OfflineDAoC-v0.36c/), re-reads every entry of every part against the manifest, and
writes the download manifest Get-OfflineDAoC.ps1 reads (Mode "newclient": it installs v0.36b (or v0.36) first, then unpacks each
part into the game folder and deletes it before the next, so the download never needs twice its size on disk):
  <out>/v0.36c/  OfflineDAoC-v0.36c-part01.zip ... , download-manifest.json, SHA256SUMS.txt
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

SEVEN_ZIP = Path(r"C:\Program Files\7-Zip\7z.exe")
VERSION = "0.36c"
BASE_VERSION = "0.36b"
BASE_CLIENT_SHA256 = "e1d471bb19108610ab9c8ca77dd41af40afe716685b03f4cdeda88c05678463b"
# The new client also plays a 0.36 (classic classes only) game: the launcher tells it the server has no Sluaghbinder.
CLASSIC_VERSION = "0.36"
CLASSIC_CLIENT_SHA256 = "f55ed6b068e22ce8e1106871c2fad6ee10c18390bbb8b5dc772219ad8c8b83bb"
PART_BUDGET = 1_850_000_000          # unpacked bytes per part; a part's zip is never larger than what it holds
ROOT_FILES = ("START OFFLINE DAOC - NEW CLIENT.cmd", "READ ME - NEW CLIENT.txt")
FORBIDDEN_FILES = {"account.txt", "claude_test_account.txt", "dev_mode.txt"}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    package, out = args.package.resolve(), args.out.resolve()
    root = package.name
    assert root == f"OfflineDAoC-v{VERSION}", f"the package folder must be named OfflineDAoC-v{VERSION}"
    folder = out / f"v{VERSION}"
    if folder.exists():
        raise SystemExit(f"{folder} exists; refusing to overwrite release assets")
    folder.mkdir(parents=True)

    files = sorted(p for p in package.rglob("*") if p.is_file())
    top = sorted({p.relative_to(package).parts[0] for p in files})
    assert top == sorted(["new-client", *ROOT_FILES]), f"unexpected top-level items: {top}"
    bad = [p.relative_to(package).as_posix() for p in files if p.name.lower() in FORBIDDEN_FILES]
    assert not bad, f"must not ship: {bad}"

    print("Hashing every package file...", flush=True)
    manifest_file = package / "new-client/PACKAGE MANIFEST.sha256"
    files = [p for p in files if p != manifest_file]
    hashes = {p.relative_to(package).as_posix(): sha(p) for p in files}
    manifest_file.write_text("".join(f"{h}  {name}\n" for name, h in hashes.items()), encoding="utf-8")
    hashes["new-client/PACKAGE MANIFEST.sha256"] = sha(manifest_file)
    files.append(manifest_file)
    total = sum(p.stat().st_size for p in files)
    print(f"{len(files)} files, {total / 1024**3:.2f} GiB", flush=True)

    # Parts in path order; the start files and the launcher come first, the VERSION.txt the helper checks comes last.
    order = sorted(files, key=lambda p: (p.name == "VERSION.txt", p.relative_to(package).as_posix().lower()))
    groups, current, size = [], [], 0
    for path in order:
        length = path.stat().st_size
        if current and size + length > PART_BUDGET:
            groups.append(current)
            current, size = [], 0
        current.append(path)
        size += length
    if current:
        groups.append(current)

    parts = []
    for number, group in enumerate(groups, start=1):
        name = f"{root}-part{number:02d}.zip"
        archive = folder / name
        print(f"Packing {name} ({len(group)} files)...", flush=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False) as listing:
            for path in group:
                listing.write(f"{root}/{path.relative_to(package).as_posix()}\n")
            list_name = listing.name
        subprocess.run([str(SEVEN_ZIP), "a", "-tzip", "-mx=5", "-mmt=on", "-scsUTF-8", "-bso0", "-bsp0",
                        str(archive), f"@{list_name}"], cwd=package.parent, check=True)
        Path(list_name).unlink()
        with zipfile.ZipFile(archive) as zf:
            seen = {}
            for item in zf.infolist():
                assert item.filename.startswith(root + "/") and "\\" not in item.filename, item.filename
                if item.is_dir():
                    continue
                digest = hashlib.sha256()
                with zf.open(item) as stream:
                    for block in iter(lambda: stream.read(1 << 20), b""):
                        digest.update(block)
                seen[item.filename[len(root) + 1:]] = digest.hexdigest()
        expected = {p.relative_to(package).as_posix(): hashes[p.relative_to(package).as_posix()] for p in group}
        assert seen == expected, f"{name} does not match the package manifest"
        assert archive.stat().st_size < 2_000_000_000, f"{name} is too large for GitHub"
        parts.append({"Name": name, "Bytes": archive.stat().st_size, "SHA256": sha(archive),
                      "UnpackedBytes": sum(p.stat().st_size for p in group), "Files": len(group)})

    manifest = {"Version": VERSION, "Title": f"Offline DAoC {VERSION} (the new client, added to 0.36b or 0.36)", "Mode": "newclient",
                "BaseVersion": BASE_VERSION, "BaseClientSHA256": BASE_CLIENT_SHA256.upper(),
                "ClassicBaseVersion": CLASSIC_VERSION, "ClassicClientSHA256": CLASSIC_CLIENT_SHA256.upper(), "RootFolder": root,
                "RootFiles": list(ROOT_FILES), "UnpackedBytes": total, "Parts": parts}
    (folder / "download-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    lines = [f"{sha(p)}  {p.name}" for p in sorted(folder.iterdir()) if p.is_file() and p.name != "SHA256SUMS.txt"]
    (folder / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files), "unpacked_bytes": total,
                      "parts": [(p["Name"], p["Bytes"], p["Files"]) for p in parts]}, indent=2), flush=True)


if __name__ == "__main__":
    main()
