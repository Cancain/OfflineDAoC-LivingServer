"""Item model -> inventory icon for the server's items (Offline DAoC Rebuilt, owner 2026-10-11).

The server's inventory packets carry an item's model, not its icon: the client looks the icon up in objects.csv
(column 3, the model's row) - build_items.global_icon puts that number on the game's icon sheets. Every model row is
written, so any item the server sends (ROG, quest rewards, crafted) shows its own picture.
Writes godot/content/items/model_icons.json.

    python pipeline/build_model_icons.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_items import object_icons, global_icon, OUT


def main():
    icons = {str(m): global_icon(n) for m, n in object_icons().items()}
    (OUT / 'model_icons.json').write_text(json.dumps(icons), encoding='utf-8')
    print(len(icons), 'models')


if __name__ == '__main__':
    main()
