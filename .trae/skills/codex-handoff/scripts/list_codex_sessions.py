#!/usr/bin/env python3
"""List Codex desktop sessions as UUID + description.

Reads ~/.codex/.codex-global-state.json, key
electron-persisted-atom-state["thread-descriptions-v1"] (a map of thread UUID
to description string). Optional keyword filters the output.

Usage: python3 list_codex_sessions.py [keyword]
"""
import json
import os
import sys

STATE = os.path.expanduser("~/.codex/.codex-global-state.json")


def main() -> int:
    if not os.path.exists(STATE):
        print(f"state file not found: {STATE}", file=sys.stderr)
        return 1
    with open(STATE, encoding="utf-8") as fh:
        data = json.load(fh)
    threads = (
        data.get("electron-persisted-atom-state", {})
        .get("thread-descriptions-v1", {})
    )
    keyword = sys.argv[1] if len(sys.argv) > 1 else ""
    found = 0
    for uuid, desc in threads.items():
        text = desc if isinstance(desc, str) else json.dumps(desc, ensure_ascii=False)
        if keyword and keyword not in text:
            continue
        print(f"{uuid}\t{text}")
        found += 1
    if not found:
        print("no matching sessions", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
