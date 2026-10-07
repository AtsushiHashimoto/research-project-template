"""Real sync/contribute cycle: template deletion, local preservation and link regeneration."""

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class SyncTest(unittest.TestCase):
    def test_rules_and_codex_sync_then_contribute(self):
        with tempfile.TemporaryDirectory(prefix="sync fixture ") as temp:
            root = Path(temp)
            project, source = root / "project", root / "source"

            def write(base, rel, text):
                path = base / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)

            def manifest(base):
                folder = base / ".claude/rules/template"
                text = "".join(
                    f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
                    for p in sorted(folder.glob("*.md"))
                )
                write(base, ".claude/rules/template/MANIFEST.sha256", text)

            write(project, ".claude/rules/template/old.md", "OLD_TEMPLATE")
            manifest(project)
            write(project, ".claude/rules/local.md", "LOCAL_RULE")
            write(project, ".codex/instructions/local.md", "LOCAL_CODEX")
            write(project, "AGENTS.md", "PROJECT_FACT")
            write(source, ".claude/rules/template/agent-runtime.md", "NEW_RUNTIME")
            manifest(source)
            write(source, ".codex/instructions.md", "ENTRY")
            write(source, ".codex/instructions/template.md", "CODEX_TEMPLATE")
            skill = "---\nname: review\ndescription: Review changes\nmetadata:\n  harness: shared\n---\n.claude/rules/template/agent-runtime.md\n"
            write(source, ".claude/skills/review/SKILL.md", skill)

            for _ in range(2):
                subprocess.run(
                    [
                        "bash",
                        str(ROOT / "scripts/template-sync-rules.sh"),
                        "--source",
                        str(source),
                        "--project-root",
                        str(project),
                    ],
                    text=True,
                    capture_output=True,
                    check=True,
                )
                # Selected file application in template-sync Step7 uses the central targets.
                for rel in (
                    ".codex/instructions.md",
                    ".codex/instructions/template.md",
                    ".claude/skills/review/SKILL.md",
                ):
                    dest = project / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source / rel, dest)
                subprocess.run(
                    [
                        "python3",
                        str(ROOT / "scripts/agent-skills.py"),
                        "--root",
                        str(project),
                    ],
                    capture_output=True,
                    check=True,
                )
            self.assertFalse((project / ".claude/rules/template/old.md").exists())
            self.assertEqual(
                (project / ".claude/rules/local.md").read_text(), "LOCAL_RULE"
            )
            self.assertEqual(
                (project / ".codex/instructions/local.md").read_text(), "LOCAL_CODEX"
            )
            self.assertEqual((project / "AGENTS.md").read_text(), "PROJECT_FACT")
            self.assertEqual(
                list((project / ".claude/rules").glob("template.bak-*")), []
            )
            self.assertEqual(
                len(json.loads((project / ".agents/skill-links.json").read_text())), 1
            )
            write(project, ".codex/instructions/template.md", "GENERIC_IMPROVEMENT")
            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/template-contribute-detect.sh"),
                    "--source",
                    str(source),
                    "--project-root",
                    str(project),
                    "--format",
                    "paths",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertEqual(
                result.stdout.splitlines(), [".codex/instructions/template.md"]
            )

    def test_hook_command_from_spaced_root_with_each_event(self):
        spec = importlib.util.spec_from_file_location(
            "hooks", ROOT / "scripts/ensure-codex-hooks.py"
        )
        hooks = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hooks)
        with tempfile.TemporaryDirectory(prefix="hook fixture ") as temp:
            root = Path(temp)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "scripts").mkdir()
            for filename in ("session-context.sh", "handoff.sh", "read-premises.sh"):
                shutil.copy2(ROOT / "scripts" / filename, root / "scripts" / filename)
            (root / ".git/claude-handoff-last").write_text(
                "7\thttps://example.invalid/issues/7\n"
            )
            fixture = {
                "title": "T7",
                "state": "OPEN",
                "labels": [],
                "parent": None,
                "comments": [
                    {
                        "authorAssociation": "OWNER",
                        "body": "## 引き継ぎ（fixture）\n### 次の一手\nHOOK_CONTEXT",
                    }
                ],
            }
            (root / "issue.json").write_text(json.dumps(fixture))
            (root / "bin").mkdir()
            gh = root / "bin/gh"
            gh.write_text(
                '#!/usr/bin/env bash\n[ "$1 $2" = "issue view" ] || exit 1\nq="."\nwhile [ $# -gt 0 ]; do case "$1" in --jq|-q) q=$2; shift;; esac; shift; done\njq -r "$q" "$HOOK_FIXTURE"\n'
            )
            gh.chmod(0o755)
            env = dict(
                os.environ,
                PATH=f"{root / 'bin'}:{os.environ['PATH']}",
                HOOK_FIXTURE=str(root / "issue.json"),
            )
            for event in ("startup", "resume", "clear", "compact"):
                result = subprocess.run(
                    ["bash", "-c", hooks.COMMAND],
                    cwd=root,
                    env=env,
                    input=json.dumps({"source": event}),
                    capture_output=True,
                    text=True,
                    check=True,
                )
                self.assertIn("#7 T7", result.stdout)
                self.assertIn("HOOK_CONTEXT", result.stdout)


if __name__ == "__main__":
    unittest.main()
