"""Turn the Living Server's bot personalities, voices and debates on or off. Default is a read-only dry run.

  python tools\\claude-version\\set_bot_social.py                          (show the current settings)
  python tools\\claude-version\\set_bot_social.py --all on --apply         (personalities, voices and debates on)
  python tools\\claude-version\\set_bot_social.py --debates off --apply    (one part off)
  python tools\\claude-version\\set_bot_social.py --all off --apply        (back to today's bots)

Parts (docs/BOT-PERSONALITIES.md, docs/bot-voices/DESIGN.md):
  --personalities  types and traits that tilt town breaks, goals, dungeons, camps and chattiness
  --voices         pre-written period lines in each bot's own writing style
  --debates        debates and long threads in /faction (needs --voices)

Needs the Living Server server build; older servers ignore these settings.
--apply needs the server, launcher and game closed; it backs up the database first.
"""
import argparse
import datetime
import os
import sqlite3
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # <playable>/tools/claude-version/
DB = ROOT / 'runtime/data/opendaoc.sqlite3.db'
DESCRIPTIONS = {
    'bot_personalities_enabled': 'Autonomous gamebots get a personality (Leveler, Socialite, Daredevil, Explorer, Crafter, No-lifer) '
                                 'and traits, fixed from their id, that tilt town breaks, solo versus group goals, dungeon choice, '
                                 'camp choice and how often they talk (see docs/BOT-PERSONALITIES.md). Hard rules never change. '
                                 'False keeps today\'s behavior.',
    'bot_voices_enabled': 'Autonomous gamebots say pre-written, period lines (docs/bot-voices/DESIGN.md) chosen by personality, '
                          'level, realm, class and situation, each in its own writing style, without repeating a line in a realm '
                          'within 6 hours. False keeps today\'s lines.',
    'bot_voices_debates': 'When bot voices are on: bots of a realm play the corpus\'s debates and long threads in /faction while '
                          'you are online, one at a time, 30-45 minutes apart, never repeating a scene until all have played.',
}
PARTS = {'personalities': 'bot_personalities_enabled', 'voices': 'bot_voices_enabled', 'debates': 'bot_voices_debates'}


def current(db):
    rows = dict(db.execute(f"SELECT `Key`, Value FROM ServerProperty WHERE `Key` IN ({','.join('?' * len(DESCRIPTIONS))})",
                           tuple(DESCRIPTIONS)).fetchall())
    return {key: rows.get(key) for key in DESCRIPTIONS}


def write(db, values):
    for key, value in values.items():
        db.execute("""INSERT INTO ServerProperty (Category, `Key`, Description, DefaultValue, Value, LastTimeRowUpdated, ServerProperty_ID)
                      VALUES ('bots', ?, ?, '', ?, ?, ?)
                      ON CONFLICT(`Key`) DO UPDATE SET Value=excluded.Value, LastTimeRowUpdated=excluded.LastTimeRowUpdated""",
                   (key, DESCRIPTIONS[key], value, datetime.datetime.now(datetime.timezone.utc).isoformat(), key))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--all', choices=['on', 'off'], help='turn personalities, voices and debates on or off together')
    for part in PARTS:
        parser.add_argument(f'--{part}', choices=['on', 'off'], help=f'turn the {part} part on or off')
    parser.add_argument('--apply', action='store_true', help='write the change (server, launcher and game closed)')
    parser.add_argument('--db', type=Path, default=DB, help=argparse.SUPPRESS)
    args = parser.parse_args()

    values = {}
    if args.all is not None:
        for key in PARTS.values():
            values[key] = 'True' if args.all == 'on' else 'False'
    for part, key in PARTS.items():
        choice = getattr(args, part)
        if choice is not None:
            values[key] = 'True' if choice == 'on' else 'False'

    with sqlite3.connect(args.db.as_uri() + '?mode=ro', uri=True) as source:
        before = current(source)
    for key, value in before.items():
        print(f'{key:26s} now: {value if value not in (None, "") else "(not set: server default)"}')
    if not values:
        print('Nothing to change. Use --all on|off or a part (--personalities, --voices, --debates).')
        return
    for key, value in values.items():
        print(f'{key:26s} new: {value}')
    debates_on = values.get('bot_voices_debates', before['bot_voices_debates'] or 'True') == 'True'
    voices_on = values.get('bot_voices_enabled', before['bot_voices_enabled'] or 'False') == 'True'
    if debates_on and not voices_on:
        print('Note: debates only play while voices are on.')
    if not args.apply:
        print('Dry run only; the database was not changed. Add --apply to write it.')
        return

    if os.name == 'nt':
        running = subprocess.check_output(['powershell', '-NoProfile', '-Command',
            'Get-Process CoreServer,DOLServer,OfflineDAoC,game -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName; exit 0'], text=True)
        if running.strip():
            raise RuntimeError('Close the server, launcher and game first: ' + running.strip())
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = args.db.parent.parent / 'server/deployment-backups' / ('bot-social-' + stamp)
    backup.mkdir(parents=True, exist_ok=False)
    with sqlite3.connect(args.db) as db:
        with sqlite3.connect(backup / 'opendaoc.sqlite3.db') as copy:
            db.backup(copy)
        db.execute('BEGIN IMMEDIATE')
        write(db, values)
        if db.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
            raise RuntimeError('Integrity check failed; rolling back')
        db.commit()
        after = current(db)
    for key, value in values.items():
        if (after[key] or '') != value:
            raise RuntimeError(f'{key} reads back as {after[key]!r}, expected {value!r}')
    print('Applied. Backup:', backup)


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        raise SystemExit(f'Not changed: {error}')
