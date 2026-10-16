"""Seal an assembled 0.36 package into verified, split release assets.

    python seal_release_036.py --package <staging>/OfflineDAoC-v0.36b --out <assets folder>

Scans the whole package for anything personal (developer or test accounts, the test-account file, DXVK, diagnostics
switches), writes PACKAGE MANIFEST.sha256 into the package, zips it (root folder OfflineDAoC-v0.36b/),
re-reads every zip entry against the manifest, splits the archive into parts below GitHub's 2 GB
limit, and writes the download manifests Get-OfflineDAoC.ps1 reads:
  <out>/v0.36b/  OfflineDAoC-v0.36b.zip.001… , download-manifest.json, SHA256SUMS.txt
  <out>/v0.36/   download-manifest.json (edition swap of the same parts), SHA256SUMS.txt
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

PART_BYTES = 1_900_000_000
SEVEN_ZIP = Path(r"C:\Program Files\7-Zip\7z.exe")
VERSION = "0.36"
EDITION_FOLDER = f"{VERSION}-no-custom-class"
EDITION_FILES = ("runtime\\data\\opendaoc.sqlite3.db", "runtime\\client-opendaoc\\app\\game.dll")


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


# Never in a public package (owner 2026-10-14): the developer's and Claude's test accounts, the test-account file, DXVK,
# the diagnostics switches. The developer's account name is checked where player data lives (runtime, tools, docs, the
# root files); old public source files under source/ already mention the developer's folders and are not player data.
FORBIDDEN_EVERYWHERE = ("claudeperf", "claudeprobe", "claude_test_account")
FORBIDDEN_PLAYER_DATA = ("account: thedo", "\\users\\thedo", "/users/thedo")
FORBIDDEN_FILES = {"account.txt", "claude_test_account.txt", "d3d9.dll", "dxvk.conf", "dev_mode.txt",
                   "memory-census.on", "gc-snapshots.on", "gc-diagnostics.off"}


def scan_package(package: Path):
    bad = []
    for path in package.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(package).as_posix()
        if rel.startswith("source/tools/") and (path.name.endswith(("_036.py", "_newclient.py")) or path.name == "sync_newclient_source.py"):
            continue                      # the release scripts name what they keep out
        if path.name.lower() in FORBIDDEN_FILES or path.suffix.lower() in (".dmp", ".gcdump", ".log"):
            bad.append(f"file {rel}")
            continue
        if path.stat().st_size > 64 * 1024 * 1024 or path.suffix.lower() in (".dds", ".nif", ".mpk", ".npk", ".png", ".wav", ".mp3"):
            continue
        data = path.read_bytes().lower()
        texts = (data, data.decode("utf-16-le", errors="ignore").encode("utf-8", errors="ignore"))
        # (compiled files carry their build folder as debug metadata, as in every earlier release; the account name
        # itself is still checked in them through FORBIDDEN_EVERYWHERE's test accounts and "account: thedo" below)
        player_data = not rel.lower().startswith("source/")
        if path.suffix.lower() in (".dll", ".pdb", ".exe"):
            texts = tuple(t.replace(b"\\users\\thedo", b"").replace(b"/users/thedo", b"") for t in texts)
        for word in FORBIDDEN_EVERYWHERE + (FORBIDDEN_PLAYER_DATA if player_data else ()):
            if any(word.encode() in t for t in texts):
                bad.append(f"{rel} contains {word!r}")
    assert not bad, "personal content would ship:\n" + "\n".join(bad[:40])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    package, out = args.package.resolve(), args.out.resolve()
    root = package.name
    assert root == f"OfflineDAoC-v{VERSION}b", f"the package folder must be named OfflineDAoC-v{VERSION}b"
    for folder in (f"v{VERSION}b", f"v{VERSION}"):   # (v0.36c may already be sealed beside them)
        if (out / folder).exists():
            raise SystemExit(f"{out / folder} exists; refusing to overwrite release assets")
    (out / f"v{VERSION}b").mkdir(parents=True)
    (out / f"v{VERSION}").mkdir(parents=True)

    print("Checking that nothing personal ships...", flush=True)
    scan_package(package)

    print("Hashing every package file...", flush=True)
    manifest_file = package / "PACKAGE MANIFEST.sha256"
    files = sorted(p for p in package.rglob("*") if p.is_file() and p != manifest_file)
    hashes = {p.relative_to(package).as_posix(): sha(p) for p in files}
    manifest_file.write_text("".join(f"{h}  {name}\n" for name, h in hashes.items()), encoding="utf-8")
    total = sum(p.stat().st_size for p in files)
    print(f"{len(files)} files, {total / 1024**3:.2f} GiB", flush=True)

    archive = out / f"{root}.zip"
    print("Zipping...", flush=True)
    subprocess.run([str(SEVEN_ZIP), "a", "-tzip", "-mx=5", "-mmt=on", "-bso0", "-bsp0", str(archive), root],
                   cwd=package.parent, check=True)

    print("Verifying every zip entry against the manifest...", flush=True)
    with zipfile.ZipFile(archive) as zf:
        entries = [i for i in zf.infolist() if not i.is_dir()]
        assert all(i.filename.startswith(root + "/") and "\\" not in i.filename for i in zf.infolist())
        seen = {}
        for item in entries:
            digest = hashlib.sha256()
            with zf.open(item) as stream:
                for block in iter(lambda: stream.read(1 << 20), b""):
                    digest.update(block)
            seen[item.filename[len(root) + 1:]] = digest.hexdigest()
    expected = dict(hashes)
    expected["PACKAGE MANIFEST.sha256"] = sha(manifest_file)
    assert seen == expected, "zip contents do not match the package manifest"
    archive_sha = sha(archive)

    print("Splitting into parts...", flush=True)
    parts = []
    with archive.open("rb") as source:
        index = 1
        while True:
            block = source.read(PART_BYTES)
            if not block:
                break
            name = f"{root}.zip.{index:03d}"
            (out / f"v{VERSION}b" / name).write_bytes(block)
            parts.append({"Name": name, "Bytes": len(block), "SHA256": hashlib.sha256(block).hexdigest()})
            index += 1
    archive.unlink()

    edition_root = package / "editions" / EDITION_FOLDER
    full = {"Version": f"{VERSION}b", "Title": f"Offline DAoC {VERSION}b (with the Sluaghbinder)", "RootFolder": root,
            "ArchiveSHA256": archive_sha, "ArchiveBytes": sum(p["Bytes"] for p in parts), "Parts": parts}
    edition = {"Version": VERSION, "Title": f"Offline DAoC {VERSION} (classic classes only)", "Mode": "edition",
               "BaseVersion": f"{VERSION}b", "EditionFolder": EDITION_FOLDER,
               "EditionFiles": [{"Path": path, "SHA256": sha(edition_root / path.replace("\\", "/"))} for path in EDITION_FILES]}
    (out / f"v{VERSION}b/download-manifest.json").write_text(json.dumps(full, indent=2) + "\n", encoding="utf-8")
    (out / f"v{VERSION}/download-manifest.json").write_text(json.dumps(edition, indent=2) + "\n", encoding="utf-8")
    for folder in (f"v{VERSION}b", f"v{VERSION}"):
        lines = [f"{sha(p)}  {p.name}" for p in sorted((out / folder).iterdir()) if p.is_file() and p.name != "SHA256SUMS.txt"]
        if folder == f"v{VERSION}b":
            lines.append(f"{archive_sha}  {root}.zip (joined parts)")
        (out / folder / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"files": len(files) + 1, "unpacked_bytes": total, "archive_sha256": archive_sha,
                      "parts": [(p["Name"], p["Bytes"]) for p in parts]}, indent=2), flush=True)


if __name__ == "__main__":
    main()
