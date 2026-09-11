#!/usr/bin/env python3
"""Verify deployed HTML and every exported browser asset against the local build."""
import hashlib
from pathlib import Path
import sys
from urllib.request import urlopen

root = Path(sys.argv[1])
origin = sys.argv[2].rstrip('/')
count = 0
for path in sorted(root.rglob('*')):
    relative = path.relative_to(root)
    if not path.is_file() or any(part.startswith('.') for part in relative.parts):
        continue
    if str(relative) == '404.html':
        continue
    url = origin + ('/' if str(relative) == 'index.html' else '/' + str(relative))
    with urlopen(url, timeout=60) as response:
        actual = response.read()
    if hashlib.sha256(actual).digest() != hashlib.sha256(path.read_bytes()).digest():
        raise SystemExit(f'website: deployed content mismatch: {url}')
    # Check the public chapter URL as well as the literal object key.
    if relative.name == "index.html" and str(relative) != "index.html":
        route_url = origin + "/" + relative.parent.as_posix() + "/"
        with urlopen(route_url, timeout=60) as response:
            if hashlib.sha256(response.read()).digest() != hashlib.sha256(path.read_bytes()).digest():
                raise SystemExit(f"website: deployed route mismatch: {route_url}")
    count += 1
print(f'website: verified {count} deployed files at {origin}')
