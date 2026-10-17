"""Check the names the server puts into bot chat at run time (not in the .lines files) against the corpus rules.

  python tools/bot-voices/check_runtime_names.py     (exit 1 on any problem; run by CI)

The corpus builder checks every written line, but slot values chosen in code skip it: the dungeons
AutonomousBotVoices.DungeonFor names, and the words bot guild names are built from
(AutonomousBotGuildPlanner). Both are checked here with the same out-of-era and banned-word rules
(audit 2026-10-16: "the Catacombs of Cardova" and "Azure Tower" had slipped through).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_corpus import BANNED_RE  # noqa: E402  (same rules as the corpus)

AUTONOMOUS = ROOT / 'source/server/GameServer/bots/autonomous'


def dungeon_names():
    text = (AUTONOMOUS / 'AutonomousBotVoices.cs').read_text(encoding='utf-8')
    body = text[text.index('public static string DungeonFor'):]
    body = body[:body.index('#endregion') if '#endregion' in body else len(body)]
    return re.findall(r'\("([^"]+)",\s*\d+,\s*\d+\)', body)


def guild_words():
    text = (AUTONOMOUS / 'AutonomousBotGuildPlanner.cs').read_text(encoding='utf-8')
    start = text.index('private static readonly RealmWords Albion')
    end = text.index('CasualNames', start)
    words = re.findall(r'"([^"{}]+)"', text[start:end])
    casual = text[end:text.index('];', end)]
    return words + re.findall(r'"([^"{}]+)"', casual)


def main():
    problems = []
    dungeons = dungeon_names()
    if len(dungeons) < 12:
        problems.append(f'found only {len(dungeons)} dungeon names in DungeonFor; the checker needs updating')
    for kind, names in (('dungeon', dungeons), ('guild word', guild_words())):
        for name in names:
            hit = BANNED_RE.search(name)
            if hit:
                problems.append(f'{kind} "{name}": out-of-era or banned word "{hit.group(0)}"')
    if problems:
        print(f'{len(problems)} problem(s):')
        for problem in problems:
            print('  ' + problem)
        raise SystemExit(1)
    print(f'runtime names ok: {len(dungeons)} dungeons, {len(guild_words())} guild words')


if __name__ == '__main__':
    main()
