"""carry_social_tables.py on small temporary databases. No real install is read or written.

    python tools/claude-version/tests/test_carry_social_tables.py
"""
import contextlib
import io
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import carry_social_tables as tool  # noqa: E402

BASE = """
CREATE TABLE `offline_world_bots` (`BotId` BIGINT NOT NULL, `Name` TEXT NOT NULL DEFAULT '', PRIMARY KEY (`BotId`));
CREATE TABLE `Guild` (`GuildID` VARCHAR(255) DEFAULT NULL, `GuildName` VARCHAR(255) DEFAULT NULL,
  `Guild_ID` VARCHAR(255) NOT NULL DEFAULT '', PRIMARY KEY (`Guild_ID`));
"""
SOCIAL = """
CREATE TABLE `offline_bot_guilds` (`GuildId` VARCHAR(64) NOT NULL, `Realm` INT NOT NULL, `Charter` VARCHAR(32) NOT NULL,
  `Ordinal` INT NOT NULL, `FounderBotId` BIGINT NOT NULL, `CreatedUtc` TEXT NOT NULL, `offline_bot_guilds_ID` VARCHAR(255) NOT NULL,
  PRIMARY KEY (`offline_bot_guilds_ID`));
CREATE UNIQUE INDEX `UX_offline_bot_guilds_GuildId` ON `offline_bot_guilds` (`GuildId`);
CREATE TABLE `offline_bot_guild_members` (`BotId` BIGINT NOT NULL, `GuildId` VARCHAR(64) NOT NULL, `RankLevel` INT NOT NULL,
  `JoinedUtc` TEXT NOT NULL, PRIMARY KEY (`BotId`));
CREATE TABLE `offline_bot_memory` (`BotId` BIGINT NOT NULL, `PlayerName` TEXT NOT NULL, `Grouped` INT NOT NULL,
  `offline_bot_memory_ID` VARCHAR(255) NOT NULL, PRIMARY KEY (`offline_bot_memory_ID`));
"""


def make(path, social=True, bots=(1, 2, 3), guilds=('g1',), members=((1, 'g1'), (2, 'g1')), memory=((1, 'Wrenfield', 3),)):
    with contextlib.closing(sqlite3.connect(path)) as db:
        db.executescript(BASE + (SOCIAL if social else ''))
        db.executemany('INSERT INTO offline_world_bots VALUES (?, ?)', [(b, f'Bot{b}') for b in bots])
        db.executemany('INSERT INTO Guild VALUES (?, ?, ?)', [(g, g.upper(), g) for g in guilds])
        if social:
            db.executemany("INSERT INTO offline_bot_guilds VALUES (?, 1, 'Social', 0, 1, 'now', ?)", [(g, g) for g in guilds])
            db.executemany("INSERT INTO offline_bot_guild_members VALUES (?, ?, 9, 'now')", members)
            db.executemany('INSERT INTO offline_bot_memory VALUES (?, ?, ?, ?)', [(*m, f'm{i}') for i, m in enumerate(memory)])
        db.commit()


def rows(path, table):
    with contextlib.closing(sqlite3.connect(path)) as db:
        return db.execute(f'SELECT * FROM "{table}" ORDER BY 1').fetchall()


class CarrySocialTables(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / 'new/runtime/data').mkdir(parents=True)
        (self.dir / 'new/runtime/server').mkdir(parents=True)
        (self.dir / 'old/runtime/data').mkdir(parents=True)
        self.old = self.dir / 'old/runtime/data/opendaoc.sqlite3.db'
        self.new = self.dir / 'new/runtime/data/opendaoc.sqlite3.db'
        make(self.old)

    def run_tool(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), mock.patch.object(tool, 'running_reason', return_value=None):
            code = tool.main(['--from', str(self.dir / 'old'), '--db', str(self.new), *args])
        return code, out.getvalue()

    def test_dry_run_changes_nothing(self):
        make(self.new, social=False)
        code, out = self.run_tool()
        self.assertEqual(code, 0, out)
        self.assertIn('offline_bot_guild_members: 2 rows', out)
        self.assertNotIn('offline_bot_guilds', [r[0] for r in sqlite3.connect(self.new).execute(
            "SELECT name FROM sqlite_master WHERE type='table'")])

    def test_copies_into_a_save_that_lacks_the_tables(self):
        # The new 0.37 save, transferred by the game but never started with the Living Server build.
        make(self.new, social=False)
        code, out = self.run_tool('--apply')
        self.assertEqual(code, 0, out)
        self.assertEqual(rows(self.new, 'offline_bot_guild_members'), rows(self.old, 'offline_bot_guild_members'))
        self.assertEqual(rows(self.new, 'offline_bot_memory'), rows(self.old, 'offline_bot_memory'))
        with contextlib.closing(sqlite3.connect(self.new)) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM sqlite_master WHERE name='UX_offline_bot_guilds_GuildId'").fetchone()[0], 1)
        self.assertTrue(list((self.dir / 'new/runtime/server/deployment-backups').glob('carry-social-*/opendaoc.sqlite3.db')))

    def test_replaces_empty_tables_and_is_repeatable(self):
        make(self.new, social=True, guilds=(), members=(), memory=())
        self.assertEqual(self.run_tool('--apply')[0], 0)
        first = rows(self.new, 'offline_bot_guild_members')
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual(rows(self.new, 'offline_bot_guild_members'), first)
        self.assertEqual(len(first), 2)

    def test_refuses_before_the_games_transfer(self):
        make(self.new, social=False, bots=())
        code, out = self.run_tool('--apply')
        self.assertEqual(code, 1)
        self.assertIn('no bots', out)

    def test_refuses_a_different_save(self):
        make(self.new, social=False, bots=(7, 8, 9))
        code, out = self.run_tool('--apply')
        self.assertEqual(code, 1)
        self.assertIn('guilded bots', out)

    def test_refuses_when_the_new_save_formed_its_own_bot_guilds(self):
        make(self.new, social=True, guilds=('fresh',), members=((3, 'fresh'),), memory=())
        code, out = self.run_tool('--apply')
        self.assertEqual(code, 1)
        self.assertIn('--purge', out)
        self.assertEqual(rows(self.new, 'offline_bot_guild_members'), [(3, 'fresh', 9, 'now')])

    def test_refuses_the_same_folder(self):
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stdout(io.StringIO()):
                tool.main(['--from', str(self.old), '--db', str(self.old)])


if __name__ == '__main__':
    unittest.main()
