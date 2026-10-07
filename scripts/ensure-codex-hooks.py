#!/usr/bin/env python3
"""Append the shared session context hook; never change personal permission settings."""

import argparse
import json
import sys
from pathlib import Path

COMMAND = 'bash "$(git rev-parse --show-toplevel)/scripts/session-context.sh"'
MATCHER = "^(startup|resume|clear|compact)$"


def ensure(root, check=False):
    folder = root / ".codex"
    path = folder / "hooks.json"
    if folder.is_symlink() or path.is_symlink():
        raise ValueError(".codex and hooks.json must be repo-local regular paths")
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
        raise TypeError(f"invalid hooks object: {path}")
    groups = data.get("hooks", {}).get("SessionStart", [])
    if not isinstance(groups, list) or any(
        not isinstance(g, dict) or not isinstance(g.get("hooks", []), list)
        for g in groups
    ):
        raise ValueError(f"invalid SessionStart groups: {path}")
    matching = [
        h
        for g in groups
        for h in g.get("hooks", [])
        if isinstance(h, dict) and h.get("command") == COMMAND
    ]
    if any(h.get("type") != "command" for h in matching):
        raise ValueError("existing context hook must have type command; kept unchanged")
    found = bool(matching)
    if not found:
        if check:
            raise ValueError("hook missing: python3 scripts/ensure-codex-hooks.py")
        data.setdefault("hooks", {}).setdefault("SessionStart", []).append(
            {
                "matcher": MATCHER,
                "hooks": [
                    {
                        "type": "command",
                        "command": COMMAND,
                        "timeout": 60,
                        "additionalContextLimit": 12000,
                    }
                ],
            }
        )
        folder.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(
        "[codex-hooks] registered; review/trust it in /hooks (registration is not activation)"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        ensure(args.root.resolve(), args.check)
    except (TypeError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"[codex-hooks] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
