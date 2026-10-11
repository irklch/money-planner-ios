#!/usr/bin/env bash
# Печатает UDID доступного симулятора iPhone с iOS 26+ (самая новая среда выполнения).
# Использование: DEST_ID=$(scripts/ci-simulator.sh)
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS-" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.rsplit("iOS-", 1)[1].split("-"))
    if version < (26, 0):
        continue
    for d in devices:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            if best is None or version > best[0]:
                best = (version, d["udid"], d["name"])
if best is None:
    sys.exit("No available iPhone simulator with iOS 26+")
print(best[1])
version = ".".join(str(part) for part in best[0])
print("Using %s (iOS %s)" % (best[2], version), file=sys.stderr)
'
