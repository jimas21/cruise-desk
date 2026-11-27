"""Prints the UDID of an available iPhone simulator on the newest iOS runtime (for `xcodebuild test`).

Usage: xcrun simctl list devices available -j | python3 ci/pick_simulator.py
"""
import json
import re
import sys


def version(runtime: str) -> tuple[int, ...]:
    match = re.search(r"iOS-([0-9-]+)$", runtime)
    return tuple(int(p) for p in match.group(1).split("-") if p) if match else ()


def main() -> int:
    devices = json.load(sys.stdin)["devices"]
    for runtime in sorted((r for r in devices if version(r)), key=version, reverse=True):
        for device in devices[runtime]:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                print(device["udid"])
                print(f"Simulator: {device['name']} ({runtime.rsplit('.', 1)[-1]})", file=sys.stderr)
                return 0
    print("::error::No iPhone simulator is available on this runner.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
