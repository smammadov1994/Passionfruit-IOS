#!/usr/bin/env python3
"""Checks the things XcodeGen and the Swift compiler would trip over at project level.

Run from anywhere:  python3 ios/Tools/check_project.py

1. Every path named in project.yml exists (sources, fileGroups, StoreKit config, entitlements dir).
2. Every folder under Tempo/ is covered by a `sources` entry of the app target.
3. No two files in a target share a basename (Xcode refuses duplicate object file names).
4. No two top-level types in a target share a name, unless both are private to different files.
"""
import os
import re
import sys
from collections import defaultdict

IOS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
problems = []


def read(path):
    with open(path, encoding='utf-8') as handle:
        return handle.read()


yml = read(os.path.join(IOS, 'project.yml'))

# 1. paths named in project.yml
named = set(re.findall(r'^\s*-\s*path:\s*(\S+)\s*$', yml, re.M))
group_block = re.search(r'^fileGroups:\n((?:\s+-\s+\S+\n)+)', yml, re.M)
if group_block:
    named.update(re.findall(r'-\s+(\S+)', group_block.group(1)))
named.update(re.findall(r'storeKitConfiguration:\s*(\S+)', yml))
for rel in sorted(named):
    if not os.path.exists(os.path.join(IOS, rel)):
        problems.append(f'project.yml names a path that does not exist: {rel}')
for key, rel in re.findall(r'^\s*(info|entitlements):\n\s+path:\s*(\S+)', yml, re.M):
    if not os.path.isdir(os.path.join(IOS, os.path.dirname(rel))):
        problems.append(f'{key} path has no folder: {rel}')

# 2. source folders
targets = {'Tempo': 'Tempo', 'TempoTests': 'TempoTests'}
for target, folder in targets.items():
    if folder not in named:
        problems.append(f'target {target}: folder {folder} is not a sources path in project.yml')
for entry in sorted(os.listdir(IOS)):
    full = os.path.join(IOS, entry)
    if os.path.isdir(full) and any(name.endswith('.swift') for _, _, files in os.walk(full) for name in files):
        if entry not in named:
            problems.append(f'folder with Swift files is not in project.yml: {entry}')

DECL = re.compile(
    r'^((?:@\w+(?:\([^)]*\))?\s+)*)((?:(?:public|internal|private|fileprivate|final|indirect|nonisolated)\s+)*)'
    r'(struct|class|enum|protocol|actor|typealias)\s+([A-Z]\w*)', re.M)

for target, folder in targets.items():
    basenames = defaultdict(list)
    types = defaultdict(list)
    for root, _, files in os.walk(os.path.join(IOS, folder)):
        if '.xcassets' in root:
            continue  # asset catalogs are compiled as one unit; their Contents.json files never clash
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, IOS)
            if name.endswith(('.swift', '.json', '.xcstrings', '.storekit', '.plist')):
                basenames[name].append(rel)
            if not name.endswith('.swift'):
                continue
            for match in DECL.finditer(read(path)):
                is_private = bool(re.search(r'\b(private|fileprivate)\b', match.group(2)))
                types[match.group(4)].append((rel, is_private))
    # 3. basenames
    for name, paths in sorted(basenames.items()):
        if len(paths) > 1:
            problems.append(f'{target}: duplicate file name {name}: {", ".join(paths)}')
    # 4. top-level type names (column 0 only, so nested types are not counted)
    for name, places in sorted(types.items()):
        if len(places) < 2:
            continue
        files = {rel for rel, _ in places}
        all_private = all(private for _, private in places)
        if all_private and len(files) == len(places):
            continue
        where = ', '.join(f'{rel}{" (private)" if private else ""}' for rel, private in places)
        problems.append(f'{target}: duplicate type {name}: {where}')
    print(f'{target}: {sum(len(v) for v in basenames.values())} files, {len(types)} top-level type names')

for problem in problems:
    print('PROBLEM', problem)
print(f'{len(problems)} problems')
sys.exit(1 if problems else 0)
