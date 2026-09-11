#!/usr/bin/env bash
# The name of the newest iPhone simulator this machine actually has, for `make test-ios`.
#
# CI runners carry whatever simulators their Xcode image shipped with, and pinning a device by
# name in the workflow means a green build breaks the day the image moves. This asks the
# machine instead: the newest iOS runtime it has, and the highest-numbered iPhone in it.
set -euo pipefail

xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, re, sys

devices = json.load(sys.stdin)["devices"]


def runtime_order(identifier):
    """Sort key for a runtime identifier, newest last."""
    version = re.search(r"iOS-([0-9-]+)$", identifier)
    if not version:
        return ()
    return tuple(int(part) for part in version.group(1).split("-"))


def device_order(name):
    """Sort key for a device name: model number first, then Pro Max over Pro over plain."""
    number = re.search(r"\d+", name)
    rank = 3 if "Pro Max" in name else 2 if "Pro" in name else 1 if "Air" in name else 0
    return (int(number.group()) if number else 0, rank, name)


best = None
for identifier, entries in devices.items():
    if "iOS" not in identifier:
        continue
    names = [entry["name"] for entry in entries if entry["name"].startswith("iPhone")]
    if not names:
        continue
    candidate = (runtime_order(identifier), device_order(max(names, key=device_order)))
    name = max(names, key=device_order)
    if best is None or candidate > best[0]:
        best = (candidate, name)

if best is None:
    sys.exit("no iPhone simulator is available on this machine")
print(best[1])
'
