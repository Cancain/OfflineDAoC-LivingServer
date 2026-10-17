"""The creation lore of classes the client's charman/summary.txt doesn't have (owner 2026-10-15: "the old client has lore
for sluaghbinder built in"): the 0.36b game.dll carries each added class's name and its description as two strings
side by side ("Sluaghbinder\\0...\\0Sluaghbinders are Hibernian battle-mystics ..."). Read from the client's own game.dll
into content/pregame/pregame.json "class_lore" {class name: text}; the create screen shows it for that class (any
race), where summary.txt's race + base text is missing.

    python pipeline/build_class_lore.py
"""
import json, re
from assets_pipeline import CLIENT, ROOT

PREGAME = ROOT / 'godot/content/pregame/pregame.json'
CLASSES = ROOT / 'godot/content/rules/server_classes.json'
# the server's classes with a base class in summary.txt (godot/game/pregame.gd SERVER_BASE): their lore is there
HAVE_SUMMARY = {'Armsman', 'Mercenary', 'Paladin', 'Reaver', 'Cleric', 'Friar', 'Cabalist', 'Sorcerer', 'Theurgist',
                'Wizard', 'Infiltrator', 'Minstrel', 'Scout', 'Necromancer', 'Warrior', 'Thane', 'Berserker', 'Skald',
                'Savage', 'Healer', 'Shaman', 'Runemaster', 'Spiritmaster', 'Bonedancer', 'Hunter', 'Shadowblade',
                'Blademaster', 'Champion', 'Hero', 'Bard', 'Druid', 'Warden', 'Eldritch', 'Enchanter', 'Mentalist',
                'Nightshade', 'Ranger', 'Animist', 'Valewalker'}


def lore_in_dll(dll: bytes, name: str) -> str:
    """The description stored right after the class's name string: '<name>\\0' padding '<text>\\0'."""
    for m in re.finditer(re.escape(name.encode('latin1')) + rb'\x00+', dll):
        start = m.end()
        end = dll.find(b'\x00', start)
        text = dll[start:end].decode('latin1', errors='replace')
        if len(text) > 40 and text.lower().startswith(name.lower()):
            return text.strip()
    return ''


def main():
    dll = (CLIENT / 'game.dll').read_bytes()
    classes = json.loads(CLASSES.read_text(encoding='utf-8')).get('classes', {})
    lore = {}
    for c in classes.values():
        name = str(c.get('name', ''))
        if name and name not in HAVE_SUMMARY:
            text = lore_in_dll(dll, name)
            if text:
                lore[name] = text
            print(name, '->', repr(text[:80]) if text else 'no lore in game.dll')
    meta = json.loads(PREGAME.read_text(encoding='utf-8'))
    meta['class_lore'] = lore
    PREGAME.write_text(json.dumps(meta, indent=1), encoding='utf-8')
    print(len(lore), 'class lore entries ->', PREGAME)


if __name__ == '__main__':
    main()
