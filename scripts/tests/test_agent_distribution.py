"""Distribution preserves project instructions, local rules and generated-link ownership."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class DistributionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="distribution fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)

    def template_fixture(self):
        import shutil

        seed = self.root / "template-seed"
        if not seed.exists():
            shutil.copytree(
                ROOT,
                seed,
                symlinks=True,
                ignore=shutil.ignore_patterns(
                    ".git",
                    ".venv",
                    "data",
                    "worktrees",
                    ".agents",
                    "__pycache__",
                    "*.pyc",
                    ".pytest_cache",
                ),
            )
        return seed

    def test_unconnected_agents_and_symlink_preflight(self):
        source, target = self.root / "source", self.root / "target"
        self.write(source / "AGENTS.md", "generic .codex/instructions.md")
        self.write(source / ".claude/CLAUDE.md", "@../AGENTS.md\n")
        self.write(target / "AGENTS.md", "existing project facts")
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; install_agent_instructions "$2" "$3"',
                "test",
                str(ROOT / "scripts/install-agent-instructions.sh"),
                str(source),
                str(target),
            ],
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("MIGRATION_REQUIRED", result.stderr)
        self.assertEqual((target / "AGENTS.md").read_text(), "existing project facts")
        outside = self.root / "outside"
        outside.write_text("PROTECTED")
        for rel in (
            "install.sh",
            "scripts",
            ".claude/skills",
            "AGENTS.md.template",
            ".claude/CLAUDE.md.template",
            ".codex/instructions.md",
            ".codex/instructions/template.md",
        ):
            path = target / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists():
                path.unlink()
            path.symlink_to(outside)
            result = subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; agent_instruction_preflight "$2"',
                    "test",
                    str(ROOT / "scripts/install-agent-instructions.sh"),
                    str(target),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(outside.read_text(), "PROTECTED")
            path.unlink()

    def test_legacy_nonforce_stops_before_codex_copy(self):
        import shutil

        bin_dir = self.root / "bin"
        script = bin_dir / "git"
        self.write(
            script,
            '#!/usr/bin/env bash\nif [ "$1" = clone ]; then\n mkdir -p "${!#}"\n cp -R "$TEMPLATE_FIXTURE/." "${!#}/"\nelse\n exec "$REAL_GIT" "$@"\nfi\n',
        )
        script.chmod(0o755)
        env = dict(
            os.environ,
            PATH=f"{bin_dir}:{os.environ['PATH']}",
            TEMPLATE_FIXTURE=str(self.template_fixture()),
            REAL_GIT=shutil.which("git"),
        )
        target = self.root / "legacy"
        self.write(target / ".claude/CLAUDE.md", "LEGACY_PROJECT_FACT")
        self.write(
            target / ".claude/skills/issue-start/SKILL.md",
            "---\ndescription: legacy\n---\nbody",
        )
        self.write(target / "scripts/old.sh", "LEGACY_SCRIPT")
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), str(target)],
            env=env,
            text=True,
            input="",
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MIGRATION_REQUIRED", result.stdout + result.stderr)
        self.assertIn("template-sync", result.stdout + result.stderr)
        self.assertFalse((target / ".codex").exists())
        self.assertEqual(
            (target / ".claude/CLAUDE.md").read_text(), "LEGACY_PROJECT_FACT"
        )
        self.assertEqual((target / "scripts/old.sh").read_text(), "LEGACY_SCRIPT")
        self.assertTrue((target / "AGENTS.md.template").is_file())

    def test_four_instruction_install_cases(self):
        source = self.root / "source"
        self.write(source / "AGENTS.md", "generic .codex/instructions.md")
        self.write(source / ".claude/CLAUDE.md", "@../AGENTS.md\n")
        for has_common, has_claude in (
            (False, False),
            (False, True),
            (True, False),
            (True, True),
        ):
            target = self.root / f"target-{has_common}-{has_claude}"
            target.mkdir()
            if has_common:
                self.write(target / "AGENTS.md", "project .codex/instructions.md")
            if has_claude:
                self.write(target / ".claude/CLAUDE.md", "project legacy")
            result = subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; install_agent_instructions "$2" "$3"; printf "%s %s" "$AGENT_INSTRUCTIONS_INSTALLED" "$AGENT_MIGRATION_REQUIRED"',
                    "test",
                    str(ROOT / "scripts/install-agent-instructions.sh"),
                    str(source),
                    str(target),
                ],
                text=True,
                capture_output=True,
                check=True,
            )
            if has_common:
                self.assertEqual(
                    (target / "AGENTS.md").read_text(), "project .codex/instructions.md"
                )
            if has_claude:
                self.assertEqual(
                    (target / ".claude/CLAUDE.md").read_text(), "project legacy"
                )
                self.assertIn("MIGRATION_REQUIRED", result.stderr)
            else:
                self.assertEqual(
                    (target / ".claude/CLAUDE.md").read_text(), "@../AGENTS.md\n"
                )
                self.assertNotIn("MIGRATION_REQUIRED", result.stderr)
            if has_claude and not has_common:
                self.assertFalse((target / "AGENTS.md").exists())
                self.assertTrue((target / "AGENTS.md.template").exists())

    def test_targets_single_source_and_local_exclusion(self):
        def targets(mode):
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/template-targets.sh"), mode],
                text=True,
                capture_output=True,
                check=True,
            )
            return set(result.stdout.splitlines())

        install, sync = targets("install"), targets("sync")
        self.assertTrue(sync <= install)
        self.assertIn(".dev", install)
        self.assertNotIn(".dev", sync)
        self.assertEqual(targets("reference"), {"AGENTS.md", ".claude/CLAUDE.md"})
        for mode in ("install", "sync", "contribute-files", "contribute-dirs"):
            self.assertNotIn(".codex/instructions/local.md", targets(mode))
            self.assertNotIn(".agents/skills", targets(mode))
        self.assertIn(".codex/instructions/template.md", targets("contribute-files"))

    @unittest.skipUnless(
        (ROOT / "install.sh").exists(),
        "installer is not distributed in this checkout",
    )
    def test_real_installer_new_and_force_preservation(self):
        # Only the network clone is replaced. Real installer, shell, JSON merge and git execute.
        bin_dir = self.root / "bin"
        script = bin_dir / "git"
        self.write(
            script,
            '#!/usr/bin/env bash\nif [ "$1" = clone ]; then\n  mkdir -p "${!#}"\n  cp -R "$TEMPLATE_FIXTURE/." "${!#}/"\nelse\n  exec "$REAL_GIT" "$@"\nfi\n',
        )
        script.chmod(0o755)
        import shutil

        env = dict(
            os.environ,
            PATH=f"{bin_dir}:{os.environ['PATH']}",
            TEMPLATE_FIXTURE=str(self.template_fixture()),
            REAL_GIT=shutil.which("git"),
        )
        target = self.root / "project"
        target.mkdir()
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), str(target)],
            env=env,
            text=True,
            input="",
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((target / ".agents/skills/issue-start/SKILL.md").is_file())
        self.assertIn("@../AGENTS.md", (target / ".claude/CLAUDE.md").read_text())
        self.write(target / "AGENTS.md", "PROJECT_FACT .codex/instructions.md")
        self.write(target / ".codex/instructions/local.md", "LOCAL_CODEX")
        self.write(target / ".claude/rules/local.md", "LOCAL_RULE")
        spec = target / ".spec/invariants.md"
        spec.write_text(spec.read_text() + "\nPROJECT_INVARIANT\n")
        hooks = target / ".codex/hooks.json"
        data = json.loads(hooks.read_text())
        data["custom"] = True
        hooks.write_text(json.dumps(data))
        result = subprocess.run(
            ["bash", str(ROOT / "install.sh"), "--force", str(target)],
            env=env,
            text=True,
            input="",
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            (target / "AGENTS.md").read_text(), "PROJECT_FACT .codex/instructions.md"
        )
        self.assertEqual(
            (target / ".codex/instructions/local.md").read_text(), "LOCAL_CODEX"
        )
        self.assertEqual((target / ".claude/rules/local.md").read_text(), "LOCAL_RULE")
        self.assertIn("PROJECT_INVARIANT", spec.read_text())
        self.assertTrue(json.loads(hooks.read_text())["custom"])

        # Force must reject nested file/directory symlinks before copying anything.
        outside = self.root / "outside protected"
        outside.write_text("PROTECTED")
        for relative in (
            "scripts/handoff.sh",
            ".claude/skills/review/SKILL.md",
            ".claude/skills/review-spec/references",
        ):
            path = target / relative
            existed = path.exists()
            backup = path.with_name(path.name + ".preserved")
            if existed:
                path.rename(backup)
            path.symlink_to(outside)
            sentinel = target / ".claude/model-policy.json"
            sentinel.write_text("PRESERVE_BEFORE_COPY")
            result = subprocess.run(
                ["bash", str(ROOT / "install.sh"), "--force", str(target)],
                env=env,
                text=True,
                input="",
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("distribution path", result.stderr)
            self.assertEqual(outside.read_text(), "PROTECTED")
            self.assertEqual(sentinel.read_text(), "PRESERVE_BEFORE_COPY")
            path.unlink()
            if existed:
                backup.rename(path)


if __name__ == "__main__":
    unittest.main()
