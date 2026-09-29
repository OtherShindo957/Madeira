#!/usr/bin/env python3
"""Read Wine's explicit server SOURCES assignment; do not compile arbitrary .c files."""
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text().replace('\\\n', ' ')
match = re.search(r'^SOURCES\s*=\s*(.*)$', text, re.M)
if not match:
    raise SystemExit('Missing server SOURCES assignment')
sources = [word for word in match[1].split() if word.endswith('.c')]
if not sources or any(not re.fullmatch(r'[a-zA-Z0-9_]+\.c', word) for word in sources):
    raise SystemExit('Unrecognized Wine server source list')
print('\n'.join(sources))
