"""Copy the new client's SOURCE (never its converted game content) into this repository's source/new-client.

    python sync_newclient_source.py --client <the new client's development folder> --repo <this repository>

What is copied: the Godot project's code (godot/project.godot, MMOEngine.csproj, nuget.config, icon, game/, tools/,
the debug probes in tests/ as code only) and the content pipeline's scripts (pipeline/*.py, spec/nif.xml,
requirements-full.txt) plus tools/build_csharp.ps1. What is never copied: godot/content (the game content converted
from the DAoC client files - players get it from the 0.36c download), godot/.godot, godot/dev_mode.txt, pipeline data
(period data, client disassembly, zone copies) and anyone's save/ folder. Files that name a developer's own folders are
refused, so the copy stays portable.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

GODOT_FILES = ("project.godot", "MMOEngine.csproj", "nuget.config", "icon.png", "icon.ico")
GODOT_DIRS = ("game", "tools", "tests")
TEST_SUFFIXES = (".gd", ".tscn", ".uid")
PIPELINE_FILES = ("requirements-full.txt", "spec/nif.xml")
PERSONAL = ("c:/users/", "c:\\users\\", "desktop/hiatus", "desktop\\hiatus",
            "claudeperf", "claudeprobe", "claude_test_account")   # developer test accounts never ship


def personal(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore").lower()
    except OSError:
        return False
    return any(marker in text for marker in PERSONAL)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    client, repo = args.client.resolve(), args.repo.resolve()
    target = repo / "source/new-client"
    for sub in ("godot", "pipeline", "tools"):
        if (target / sub).exists():
            shutil.rmtree(target / sub)          # only this repository's own copy is replaced
    copied, skipped = [], []

    def put(source: Path, relative: str):
        if source.suffix.lower() in (".gd", ".cs", ".py", ".ps1", ".tscn", ".cfg", ".json", ".txt", ".md") and personal(source):
            skipped.append(f"{relative} (names a developer folder or test account)")
            return
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        copied.append(relative)

    godot = client / "godot"
    for name in GODOT_FILES:
        put(godot / name, f"godot/{name}")
    for folder in GODOT_DIRS:
        for path in sorted((godot / folder).rglob("*")):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            rel = path.relative_to(godot).as_posix()
            if folder == "tests" and (not path.name.endswith(TEST_SUFFIXES) or (path.parent / ".gdignore").exists()):
                continue                          # the probes' code, not their captured models and screenshots
            put(path, f"godot/{rel}")
    pipeline = client / "pipeline"
    for path in sorted(pipeline.glob("*.py")):
        put(path, f"pipeline/{path.name}")
    for name in PIPELINE_FILES:
        put(pipeline / name, f"pipeline/{name}")
    put(client / "tools/build_csharp.ps1", "tools/build_csharp.ps1")
    (target / "pipeline/spec/README.txt").write_text(
        "nif.xml is the NetImmerse/Gamebryo file format description from the NifTools project\n"
        "(https://github.com/niftools/nifxml), licensed under the GNU General Public License v3.\n"
        "The pipeline's NIF readers (nif_static.py, nif_character.py) load it to read the original client's models.\n",
        encoding="utf-8", newline="\n")
    print(f"copied {len(copied)} files into {target}")
    for line in skipped:
        print("  skipped", line)


if __name__ == "__main__":
    main()
