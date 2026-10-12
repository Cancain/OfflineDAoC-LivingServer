"""Turn bot guilds on or off (docs/BOT-GUILDS.md). Default is a read-only dry run.

  python tools\\claude-version\\set_bot_guilds.py                       (show the current settings)
  python tools\\claude-version\\set_bot_guilds.py --on --apply          (turn bot guilds on)
  python tools\\claude-version\\set_bot_guilds.py --share 0.6 --apply   (60% of eligible bots in guilds)
  python tools\\claude-version\\set_bot_guilds.py --off --apply         (every gamebot guildless again)
  python tools\\claude-version\\set_bot_guilds.py --claims off --apply  (one part off; the others stay on)

Parts, each on by default and only active while bot guilds are on:
  --social     guild chat, greetings, replies to your /gu, recruiting in /faction
  --recruit    bot officers invite you to their guild (yes/no dialog)
  --claims     bot guilds claim keeps their realm takes, and defend them first
  --economy    dues from real loot, merit points, guild buffs
  --alliances  each realm's RvR and raiding bot guilds form one alliance

Needs a server build with AutonomousBotGuilds.cs; older servers ignore these settings.
Turning it off keeps the saved guilds and memberships; turning it on again restores them.
--apply needs the server, launcher and game closed; it backs up the database first.
"""
import argparse
import datetime
import os
import re
import sqlite3
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # <playable>/tools/claude-version/
DB = ROOT / 'runtime/data/opendaoc.sqlite3.db'
DESCRIPTIONS = {
    'bot_guilds_enabled': 'Autonomous gamebots form and join realm guilds (see docs/BOT-GUILDS.md), and players can '
                          '/ginvite them. False keeps every gamebot guildless; saved memberships are kept.',
    'bot_guild_share': 'Share (0 to 1) of eligible autonomous gamebots that bot guild formation places in guilds.',
    'bot_guild_min_level': 'Lowest level at which an autonomous gamebot is placed in a bot guild.',
    'bot_guild_social': 'When bot guilds are on: guild members greet, congratulate and chat in guild chat when a real '
                        'member can hear, answer your /gu, and bot guild officers recruit in /faction.',
    'bot_guild_recruit_player': 'When bot guild social life is on: bot guild officers may invite you to their guild with '
                                'a yes/no dialog (when you ask for a guild, or now and then when you are nearby and unguilded).',
    'bot_guild_claims_keeps': 'When bot guilds are on: after a realm takes a keep or tower, a bot guild with enough members '
                              'inside claims it (claim_num, half for towers; guilds_claim_limit), never while a real player '
                              'of that realm is inside. Its warbands answer first when that keep is attacked.',
    'bot_guild_economy': 'When bot guilds are on: guilded gamebots pay their guild\'s dues from the real coin they loot, '
                         'their level-ups earn the guild merit points as a player\'s do, and bot guild leaders spend 1,000 '
                         'merit points on a 24-hour guild buff.',
    'bot_guild_alliances': 'When bot guilds are on: each realm\'s RvR and raiding bot guilds form one alliance (up to four '
                           'guilds); a player in one of them hears its alliance chat. Alliances with a player\'s guild are '
                           'never touched.',
}
PARTS = {'social': 'bot_guild_social', 'recruit': 'bot_guild_recruit_player', 'claims': 'bot_guild_claims_keeps',
         'economy': 'bot_guild_economy', 'alliances': 'bot_guild_alliances'}
NUMBER = re.compile(r'(0(\.[0-9]+)?|1(\.0+)?)')
LEVEL = re.compile(r'[0-9]{1,2}')


def current(db):
    rows = dict(db.execute(f"SELECT `Key`, Value FROM ServerProperty WHERE `Key` IN ({','.join('?' * len(DESCRIPTIONS))})",
                           tuple(DESCRIPTIONS)).fetchall())
    return {key: rows.get(key) for key in DESCRIPTIONS}


def write(db, values):
    for key, value in values.items():
        db.execute("""INSERT INTO ServerProperty (Category, `Key`, Description, DefaultValue, Value, LastTimeRowUpdated, ServerProperty_ID)
                      VALUES ('guild', ?, ?, '', ?, ?, ?)
                      ON CONFLICT(`Key`) DO UPDATE SET Value=excluded.Value, LastTimeRowUpdated=excluded.LastTimeRowUpdated""",
                   (key, DESCRIPTIONS[key], value, datetime.datetime.now(datetime.timezone.utc).isoformat(), key))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    switch = parser.add_mutually_exclusive_group()
    switch.add_argument('--on', action='store_true', help='turn bot guilds on')
    switch.add_argument('--off', action='store_true', help='turn bot guilds off (saved guilds are kept)')
    parser.add_argument('--share', help='share of eligible bots in guilds, 0 to 1 (default 0.7)')
    parser.add_argument('--min-level', help='lowest level that joins a bot guild, 1 to 50 (default 5)')
    for part in PARTS:
        parser.add_argument(f'--{part}', choices=['on', 'off'], help=f'turn the {part} part on or off')
    parser.add_argument('--apply', action='store_true', help='write the change (server, launcher and game closed)')
    parser.add_argument('--db', type=Path, default=DB, help=argparse.SUPPRESS)
    args = parser.parse_args()

    values = {}
    if args.on or args.off:
        values['bot_guilds_enabled'] = 'True' if args.on else 'False'
    if args.share is not None:
        if not NUMBER.fullmatch(args.share.strip()):
            raise ValueError(f'"{args.share}" is not a share from 0 to 1')
        values['bot_guild_share'] = args.share.strip()
    if args.min_level is not None:
        level = args.min_level.strip()
        if not LEVEL.fullmatch(level) or not 1 <= int(level) <= 50:
            raise ValueError(f'"{args.min_level}" is not a level from 1 to 50')
        values['bot_guild_min_level'] = str(int(level))
    for part, key in PARTS.items():
        choice = getattr(args, part)
        if choice is not None:
            values[key] = 'True' if choice == 'on' else 'False'

    with sqlite3.connect(args.db.as_uri() + '?mode=ro', uri=True) as source:
        before = current(source)
    for key, value in before.items():
        print(f'{key:26s} now: {value if value not in (None, "") else "(not set: server default)"}')
    if not values:
        print('Nothing to change. Use --on, --off, --share, --min-level or a part (--social, --claims, ...).')
        return
    for key, value in values.items():
        print(f'{key:26s} new: {value}')
    if not args.apply:
        print('Dry run only; the database was not changed. Add --apply to write it.')
        return

    if os.name == 'nt':
        running = subprocess.check_output(['powershell', '-NoProfile', '-Command',
            'Get-Process CoreServer,DOLServer,OfflineDAoC,game -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName; exit 0'], text=True)
        if running.strip():
            raise RuntimeError('Close the server, launcher and game first: ' + running.strip())
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = args.db.parent.parent / 'server/deployment-backups' / ('bot-guilds-' + stamp)
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
