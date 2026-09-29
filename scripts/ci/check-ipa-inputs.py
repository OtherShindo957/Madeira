#!/usr/bin/env python3
"""Check the existing Xcode project's native inputs without requiring Xcode."""
from collections import Counter
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]
project = root / 'app/Madeira.xcodeproj/project.pbxproj'
text = project.read_text()
errors = []
# Madeira's archive and resource references are in its Madeira group.
for line in text.splitlines():
    if 'isa = PBXFileReference;' not in line or 'sourceTree = "<group>"' not in line:
        continue
    if not any(kind in line for kind in ('archive.ar;', 'lastKnownFileType = folder;', 'archive.gzip;')):
        continue
    match = re.search(r'path = (?:"([^"]+)"|([^;]+));', line)
    if not match:
        errors.append('Unrecognized resource reference: ' + line.strip())
        continue
    relative = match[1] or match[2]
    path = (root / 'app/Madeira' / relative).resolve()
    if not path.exists() or (path.is_file() and path.stat().st_size == 0):
        errors.append('Missing or empty input: ' + str(path.relative_to(root)))
    elif path.is_dir() and not any(path.iterdir()):
        errors.append('Empty resource directory: ' + str(path.relative_to(root)))
# A duplicate object ID is ambiguous to Xcode even when the labels differ.
ids = re.findall(r'^\s*([A-Fa-f0-9]+) /\*.*?\*/ = \{', text, re.M)
for key, count in Counter(ids).items():
    if count > 1:
        errors.append(f'Duplicate Xcode object ID: {key} ({count} definitions)')
if errors:
    print('IPA build prerequisites are incomplete:\n')
    print('\n'.join('- ' + error for error in errors))
    print('\nSee docs/BUILD_IPA.md. No IPA was built. This check is not a compiler/linker test.')
    sys.exit(1)
print('Native archive/resource preflight passed; Xcode compilation is still required.')
