#!/usr/bin/env python3
"""Publish explicitly shared skills as repo-local relative links, without copies."""

import argparse
import json
import os
import re
import sys
from pathlib import Path


def shared_skills(root):
    sources = root / ".claude/skills"
    if not sources.is_dir():
        raise ValueError(f"missing skill sources: {sources}")
    result = {}
    for folder in sorted(sources.iterdir()):
        if not folder.is_dir():
            continue
        doc = folder / "SKILL.md"
        if not doc.is_file():
            raise ValueError(f"missing SKILL.md: {folder}")
        parts = doc.read_text().split("---", 2)
        if len(parts) != 3 or parts[0].strip():
            raise ValueError(f"invalid frontmatter: {doc}")
        header = parts[1]
        # The portable fields used by this repository are single-line scalars.
        values = {}
        for field in ("name", "description"):
            matches = re.findall(rf"^{field}:[ \t]*(\S[^\n]*)$", header, re.MULTILINE)
            if len(matches) != 1:
                raise ValueError(f"one nonempty {field} required: {doc}")
            raw = matches[0].strip()
            if raw.startswith('"'):
                value = json.loads(raw)
            elif raw.startswith("'"):
                if not raw.endswith("'") or len(raw) < 2:
                    raise ValueError(f"invalid quoted {field}: {doc}")
                value = raw[1:-1].replace("''", "'")
            else:
                if raw.lower() in {"true", "false", "null", "~"} or re.fullmatch(
                    r"[+-]?[0-9.]+", raw
                ):
                    raise ValueError(f"{field} must be a string: {doc}")
                value = raw
            limit = 64 if field == "name" else 1024
            if not isinstance(value, str) or not value.strip() or len(value) > limit:
                raise ValueError(
                    f"{field} must be nonempty and at most {limit} characters: {doc}"
                )
            values[field] = value
        if values["name"] != folder.name or not re.fullmatch(
            r"[a-z0-9]+(?:-[a-z0-9]+)*", folder.name
        ):
            raise ValueError(f"skill name must match its directory: {doc}")
        scopes = re.findall(
            r"^  harness:\s*(shared|claude-only)\s*$", header, re.MULTILINE
        )
        if len(scopes) != 1 or not re.search(r"^metadata:\s*$", header, re.MULTILINE):
            raise ValueError(f"declare metadata.harness shared or claude-only: {doc}")
        if scopes[0] == "shared":
            runtime = ".claude/rules/template/agent-runtime.md"
            if runtime not in parts[2] or not (root / runtime).is_file():
                raise ValueError(
                    f"shared skill must reference the runtime contract: {doc}"
                )
            result[folder.name] = f"../../.claude/skills/{folder.name}"
    return result


def sync(root, check=False):
    wanted = shared_skills(root)
    dest = root / ".agents/skills"
    state = root / ".agents/skill-links.json"
    if (root / ".agents").is_symlink() or dest.is_symlink() or state.is_symlink():
        raise ValueError(".agents, skills and skill-links.json must not be symlinks")
    if dest.exists() and not dest.is_dir():
        raise ValueError(f"skill destination is not a directory: {dest}")
    previous = json.loads(state.read_text()) if state.exists() else {}
    if not isinstance(previous, dict):
        raise TypeError(f"invalid managed-link state: {state}")
    for name, target in previous.items():
        if (
            not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name)
            or target != f"../../.claude/skills/{name}"
        ):
            raise ValueError(f"invalid managed-link ownership: {name}")
    changed = []
    # Preflight every collision before writing anything; replaced user content is never removed.
    for name in sorted(set(wanted) | set(previous)):
        link = dest / name
        exists = link.exists() or link.is_symlink()
        expected = wanted.get(name, previous.get(name))
        if exists and (not link.is_symlink() or os.readlink(link) != expected):
            raise ValueError(
                f"conflict (kept unchanged): {link}; move it explicitly before retrying"
            )
        if name in wanted and not exists:
            changed.append(("add", name))
        elif name not in wanted and exists:
            changed.append(("remove", name))
    if check:
        if changed or previous != wanted:
            raise ValueError("links need regeneration: python3 scripts/agent-skills.py")
        print(f"[agent-skills] checked {len(wanted)} shared skills")
        return
    dest.mkdir(parents=True, exist_ok=True)
    for action, name in changed:
        link = dest / name
        if action == "add":
            link.symlink_to(wanted[name])
        else:
            link.unlink()
        print(f"[agent-skills] {action}: {name}")
    data = json.dumps(wanted, indent=2, ensure_ascii=False) + "\n"
    if not state.exists() or state.read_text() != data:
        state.write_text(data)
    print(f"[agent-skills] ready: {len(wanted)} shared skills; unmanaged entries kept")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--validate-sources",
        action="store_true",
        help="preflight an existing harness without writing links",
    )
    args = parser.parse_args()
    try:
        root = args.root.resolve()
        if args.validate_sources:
            wanted = shared_skills(root)
            if not wanted:
                raise ValueError(
                    "no explicitly shared skills; upgrade the harness before generating links"
                )
            print(f"[agent-skills] valid sources: {len(wanted)} shared skills")
        else:
            sync(root, args.check)
    except (TypeError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"[agent-skills] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
