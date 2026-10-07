"""Behavioral tests for shared skill discovery, rules, hooks and model isolation."""

import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


SKILLS = module("agent-skills")
RULES = module("agent-rules")
HOOKS = module("ensure-codex-hooks")


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agent fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def skill(self, name, harness="shared"):
        self.write(".claude/rules/template/agent-runtime.md", "runtime")
        return self.write(
            f".claude/skills/{name}/SKILL.md",
            f"---\nname: {name}\ndescription: Use for testing\nmetadata:\n  harness: {harness}\n---\n.claude/rules/template/agent-runtime.md\n",
        )


class SkillsTest(Fixture):
    def test_native_metadata_boundaries(self):
        doc = self.skill("review")
        original = doc.read_text()
        for bad in ('""', '"' + "x" * 1025 + '"', "true"):
            doc.write_text(original.replace("Use for testing", bad))
            with self.assertRaises(ValueError):
                SKILLS.sync(self.root)
        doc.write_text(original.replace("Use for testing", "x" * 1024))
        SKILLS.sync(self.root)
        self.skill("a" * 65)
        with self.assertRaises(ValueError):
            SKILLS.sync(self.root)

    def test_idempotent_single_source_and_owned_removal(self):
        self.skill("review")
        self.skill("private", "claude-only")
        SKILLS.sync(self.root)
        link = self.root / ".agents/skills/review"
        self.assertEqual(os.readlink(link), "../../.claude/skills/review")
        self.assertFalse((self.root / ".agents/skills/private").exists())
        state = self.root / ".agents/skill-links.json"
        before = state.stat().st_mtime_ns
        SKILLS.sync(self.root)
        SKILLS.sync(self.root, check=True)
        self.assertEqual(state.stat().st_mtime_ns, before)
        self.write(".agents/skills/user/SKILL.md", "local")
        self.skill("next")
        shutil.rmtree(self.root / ".claude/skills/review")
        SKILLS.sync(self.root)
        self.assertFalse(link.is_symlink())
        self.assertTrue((self.root / ".agents/skills/next/SKILL.md").is_file())
        self.assertEqual(
            (self.root / ".agents/skills/user/SKILL.md").read_text(), "local"
        )

    def test_conflict_preflight_preserves_everything(self):
        self.skill("review")
        SKILLS.sync(self.root)
        link = self.root / ".agents/skills/review"
        link.unlink()
        self.write(".agents/skills/review/SKILL.md", "user replacement")
        shutil.rmtree(self.root / ".claude/skills/review")
        self.skill("another")
        with self.assertRaisesRegex(ValueError, "conflict"):
            SKILLS.sync(self.root)
        self.assertFalse((self.root / ".agents/skills/another").exists())
        self.assertEqual((link / "SKILL.md").read_text(), "user replacement")

    def test_metadata_and_parent_symlinks_rejected(self):
        doc = self.skill("review")
        doc.write_text("---\ndescription: test\n---\nbody")
        with self.assertRaises(ValueError):
            SKILLS.sync(self.root)
        self.skill("review")
        external = self.root / "external"
        external.mkdir()
        (self.root / ".agents").symlink_to(external)
        with self.assertRaisesRegex(ValueError, "symlinks"):
            SKILLS.sync(self.root)
        self.assertEqual(list(external.iterdir()), [])


class RulesTest(Fixture):
    def test_paths_braces_recursive_and_local_order(self):
        self.write(".claude/rules/template/always.md", "always")
        self.write(".claude/rules/local.md", "local override")
        self.write(
            ".claude/rules/template/conditional.md",
            '---\npaths:\n  - "scripts/**/*.{py,sh}"\n---\nconditional',
        )
        normal = RULES.selected(self.root)
        self.assertEqual(
            normal, [".claude/rules/template/always.md", ".claude/rules/local.md"]
        )
        for path in ("scripts/main.py", "scripts/sub/main.sh"):
            self.assertIn(
                ".claude/rules/template/conditional.md",
                RULES.selected(self.root, [path]),
            )
        self.assertNotIn(
            ".claude/rules/template/conditional.md",
            RULES.selected(self.root, ["src/main.py"]),
        )
        self.assertEqual(len(RULES.selected(self.root, all_rules=True)), 3)
        self.write(".claude/rules/template/bad.md", "---\nunknown: true\n---\nbody")
        with self.assertRaisesRegex(ValueError, "unsupported"):
            RULES.selected(self.root)


class HooksTest(Fixture):
    def test_merge_idempotence_and_custom_matcher(self):
        path = self.write(
            ".codex/hooks.json",
            json.dumps(
                {
                    "custom": True,
                    "hooks": {
                        "Stop": [],
                        "SessionStart": [
                            {
                                "matcher": "startup",
                                "hooks": [{"type": "command", "command": "echo other"}],
                            }
                        ],
                    },
                }
            ),
        )
        HOOKS.ensure(self.root)
        first = path.read_text()
        HOOKS.ensure(self.root)
        HOOKS.ensure(self.root, check=True)
        self.assertEqual(first, path.read_text())
        data = json.loads(first)
        self.assertTrue(data["custom"])
        self.assertEqual(len(data["hooks"]["SessionStart"]), 2)
        data["hooks"]["SessionStart"][1]["matcher"] = "resume"
        path.write_text(json.dumps(data))
        HOOKS.ensure(self.root)
        self.assertEqual(
            json.loads(path.read_text())["hooks"]["SessionStart"][1]["matcher"],
            "resume",
        )

    def test_invalid_json_preserved(self):
        path = self.write(".codex/hooks.json", '{"hooks": null}')
        with self.assertRaises((TypeError, ValueError)):
            HOOKS.ensure(self.root)
        self.assertEqual(path.read_text(), '{"hooks": null}')
        path.write_text(
            json.dumps(
                {"hooks": {"SessionStart": [{"hooks": [{"command": HOOKS.COMMAND}]}]}}
            )
        )
        before = path.read_text()
        with self.assertRaisesRegex(ValueError, "type command"):
            HOOKS.ensure(self.root)
        self.assertEqual(path.read_text(), before)


class ModelsTest(Fixture):
    def test_agent_namespace_and_failures(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        policy = {
            "roles": {"verification": {"primary": "opus", "fallback": ["sonnet"]}},
            "overrides": {},
            "disabled": [],
            "agents": {
                "codex": {
                    "roles": {"verification": {"primary": "inherit", "fallback": []}},
                    "overrides": {},
                    "disabled": [],
                }
            },
        }
        self.write(".claude/model-policy.json", json.dumps(policy))
        self.write(
            ".claude/model-policy.local.json", json.dumps({"disabled": ["opus"]})
        )

        def run(*args, env=None):
            return subprocess.run(
                ["bash", str(SCRIPTS / "resolve-model.sh"), *args],
                cwd=self.root,
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )

        self.assertEqual(run("verification").stdout.strip(), "sonnet")
        self.assertEqual(
            run("--agent", "codex", "verification").stdout.strip(), "inherit"
        )
        policy["overrides"]["verification"] = "haiku"
        self.write(".claude/model-policy.json", json.dumps(policy))
        self.assertEqual(run("verification").stdout.strip(), "haiku")
        policy["agents"]["codex"]["disabled"] = "inherit"
        self.write(".claude/model-policy.json", json.dumps(policy))
        self.assertNotEqual(run("--agent", "codex", "verification").returncode, 0)
        policy["agents"]["codex"]["disabled"] = []
        policy["agents"]["codex"]["roles"]["verification"]["fallback"] = "inherit"
        self.write(".claude/model-policy.json", json.dumps(policy))
        self.assertNotEqual(run("--agent", "codex", "verification").returncode, 0)
        policy["agents"]["codex"]["roles"]["verification"]["fallback"] = []
        self.write(".claude/model-policy.json", json.dumps(policy))
        self.assertEqual(
            run("--agent", "codex", "verification").stdout.strip(), "inherit"
        )
        self.assertNotEqual(run("--agent", "codex", "missing").returncode, 0)
        env = dict(os.environ, CODEX_MODEL_POLICY_DISABLE="inherit")
        self.assertNotEqual(
            run("--agent", "codex", "verification", env=env).returncode, 0
        )
        self.assertEqual(run("--disable", "haiku").returncode, 0)
        self.assertEqual(run("--enable", "haiku").returncode, 0)
        self.assertEqual(run("verification").stdout.strip(), "haiku")
        self.assertEqual(run("--agent", "codex", "--disable", "inherit").returncode, 0)
        self.assertNotEqual(run("--agent", "codex", "verification").returncode, 0)
        self.assertEqual(run("verification").stdout.strip(), "haiku")


if __name__ == "__main__":
    unittest.main()
