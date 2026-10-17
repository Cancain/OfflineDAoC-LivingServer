"""Compares what the stand-in server sent (cases.json) with what the new client showed (living_server_probe.json).
  python compare.py <folder with both files>     (exit 1 on any failure)
"""
import json
import sys
from pathlib import Path

folder = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
sent = json.loads((folder / 'cases.json').read_text())
seen = json.loads((folder / 'living_server_probe.json').read_text())
centre = [line.lower() for line in seen['centre']]
failures = 0
total = 0
for case in sent['cases']:
    if case['id'] == 'end':
        continue
    total += 1
    if case.get('dialog'):
        first = case['text'].split('\n')[0].upper()
        ok = any(first in box.upper() for box in seen['boxes_accepted'])
        how = 'yes/no box shown and answered'
    else:
        kinds = [kind for text, kind in seen['emitted'] if text == case['text']]
        box = seen['chat_system_box'] if case['expect_kind'] == 'system' else seen['chat_main']
        ok = kinds == [case['expect_kind']] and case['text'] in box and \
            (not case['expect_center'] or case['text'].lower() in centre)
        how = f"chat type {case['type']} shown as {kinds}" + (' and on screen' if case['expect_center'] else '')
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {case['feature']:<20} {case['id']:<18} {how}")
accepted = sent.get('acceptedCustomDialogAnswers', 0)
dialogs = sum(1 for case in sent['cases'] if case.get('dialog'))
if accepted != dialogs:
    failures += 1
    print(f'FAIL  the server got {accepted} accepted answers for {dialogs} boxes')
print(f'{total - failures} of {total} passed; the server read {accepted} ACCEPT answers as the game handles them')
sys.exit(1 if failures else 0)
