#!/usr/bin/env python3
"""List shared rules from their existing paths metadata; local rules follow template rules."""

import argparse
import fnmatch
import re
import sys
from pathlib import Path


def rule_paths(doc):
    text = doc.read_text()
    if not text.startswith("---\n"):
        return []
    parts = text.split("---", 2)
    if len(parts) != 3:
        raise ValueError(f"unterminated frontmatter: {doc}")
    lines = parts[1].splitlines()
    paths = []
    in_paths = False
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line == "paths:":
            in_paths = True
        elif in_paths and re.match(r"^\s+-\s+", line):
            value = re.sub(r"^\s+-\s+", "", line).strip().strip("\"'")
            if not value:
                raise ValueError(f"empty paths item: {doc}")
            paths.append(value)
        else:
            raise ValueError(f"unsupported rule frontmatter: {doc}: {line}")
    if not in_paths or not paths:
        raise ValueError(f"paths list required in rule frontmatter: {doc}")
    return paths


def expand(pattern):
    match = re.search(r"\{([^{}]+)\}", pattern)
    if not match:
        return [pattern]
    return [
        p
        for item in match[1].split(",")
        for p in expand(pattern[: match.start()] + item + pattern[match.end() :])
    ]


def matches(path, pattern):
    # Segment matching preserves * vs ** and allows ** to match zero directories.
    left, right = path.split("/"), pattern.split("/")

    def walk(i, j):
        if j == len(right):
            return i == len(left)
        if right[j] == "**":
            return walk(i, j + 1) or (i < len(left) and walk(i + 1, j))
        return (
            i < len(left)
            and fnmatch.fnmatchcase(left[i], right[j])
            and walk(i + 1, j + 1)
        )

    return walk(0, 0)


def selected(root, paths=(), all_rules=False):
    rules = root / ".claude/rules"
    if not (rules / "template").is_dir():
        raise ValueError(f"missing template rules: {rules}")
    files = sorted((rules / "template").glob("*.md")) + sorted(rules.glob("*.md"))
    result = []
    for doc in files:
        patterns = rule_paths(doc)
        if (
            not patterns
            or all_rules
            or any(
                matches(p, ex) for p in paths for pat in patterns for ex in expand(pat)
            )
        ):
            result.append(doc.relative_to(root).as_posix())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--all", action="store_true", help="list all rules for topic-based selection"
    )
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    try:
        root = args.root.resolve()
        paths = []
        for raw in args.paths:
            path = Path(raw)
            if path.is_absolute():
                path = path.relative_to(root)
            if ".." in path.parts:
                raise ValueError(f"path outside root: {raw}")
            paths.append(path.as_posix())
        print("\n".join(selected(root, paths, args.all)))
    except (ValueError, OSError) as exc:
        print(f"[agent-rules] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
