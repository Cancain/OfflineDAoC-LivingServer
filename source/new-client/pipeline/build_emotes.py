"""Player emotes (/wave, /bow ...): the old server's EmoteCommandHandler (commands/playercommands/emotes.cs) - which
command plays which emote (eEmote = the client's emotes.csv id -> the figure clip 'emote_<id>', build_races.py) and its
four lines (no target: to you / to others; a target: to you / to others), the 1.65 set only (the handler's first
block; its "New" blocks are later emotes). Writes godot/content/rules/emotes.json.

    python build_emotes.py"""
import json, re
from assets_pipeline import ROOT
OLD = ROOT / 'external/old_project'
SRC = OLD / 'development-source/server/GameServer/commands/playercommands/emotes.cs'
IPL = OLD / 'development-source/server/GameServer/packets/Server/IPacketLib.cs'


def main():
    text = SRC.read_text(encoding='utf-8', errors='ignore')
    body = IPL.read_text(encoding='utf-8', errors='ignore').split('enum eEmote', 1)[1].split('}', 1)[0]
    enum = {n: int(v, 16) for n, v in re.findall(r'^\s*(\w+)\s*=\s*0x([0-9a-fA-F]+),', body, re.M)}
    head = text.split('//New', 1)[0]                        # the classic block of [CmdAttribute]s
    cmds = re.findall(r'CmdAttribute\("&(\w+)", ePrivLevel\.Player, "([^"]*)"', head)
    cases = {c: (e, m) for c, e, m in
             re.findall(r'case "&(\w+)":\s*emoteID = eEmote\.(\w+);\s*emoteMessages = (\w+);', text)}
    arrays = {n: re.findall(r'"([^"]*)"', b) for n, b in
              re.findall(r'string\[\] (EMOTE_MESSAGES_\w+) = \{(.*?)\};', text, re.S)}
    out = {}
    for c, desc in cmds:
        if c not in cases:
            continue
        e, m = cases[c]
        out[c] = {'emote': enum.get(e, 0), 'description': desc, 'messages': arrays.get(m, [])}
    dest = ROOT / 'godot/content/rules/emotes.json'
    dest.write_text(json.dumps({'emotes': out, 'range_to_target': 2048, 'range_to_others': 512,
                                'source': 'old server EmoteCommandHandler (emotes.cs), classic block'}, indent=1),
                    encoding='utf-8')
    print(len(out), 'emotes:', {c: v['emote'] for c, v in out.items()})


if __name__ == '__main__':
    main()
