# Issue #165: Shared Claude Code / Codex workflow

## Goal
Keep project facts, common rules and skill bodies in one source. Add only engine-specific entry and execution adapters. Preserve existing research discipline and mandatory review gates.

## Design and state
Issue → isolated branch → reviewed specification → implementation → quality / independent reviews → draft PR → merge after acceptance → template-sync distribution.

- AGENTS.md is the canonical project instruction file; Claude imports it. Codex reads its own adapter after the shared entry.
- Shared .claude rules and skills stay in place. Explicit shared metadata generates relative .agents links with ownership checks and collision preflight.
- Role assignment stays in one model policy; Codex defaults to inherit and uses an isolated namespace. Malformed policy stops.
- Session context is common; hook registration and trust are separate. Handoff state is worktree-specific with main-only legacy compatibility.
- Targets for install/sync/contribute are declared once. Project facts, local instructions, credentials and generated links are preserved/excluded.
- Legacy instructions are never automatically overwritten. Unconnected or unupgraded harnesses report MIGRATION_REQUIRED before adding Codex files.
- API names are examples. Independent agents, wait/message/resume and nesting must exist; unavailable capabilities stop instead of self-review.

## Review decisions
Independent architecture, risk, test, fallback, compliance, logic, pattern and console UX reviews were performed against the generic implementation. Legacy preflight, entry routing, symlink protection and malformed model/hook issues were corrected and independently rechecked.
Required .spec defaults exist; project-specific template sections remain intentionally unfilled. No goal or research invariant was changed. No new implicit fallback was approved.
Explicit compatibility includes main handoff state, legacy CLAUDE evidence gathering and configured model fallback chains.

## Validation
- [x] Shared-source links, repeated generation, owned removal and conflicts.
- [x] Rule path selection, local priority, missing/invalid metadata errors.
- [x] Model isolation and legacy Claude disable/override behavior.
- [x] Hook registration merge/idempotence and invalid-type refusal.
- [x] Four instruction states, legacy non-force stop and force preservation.
- [x] Real rules-sync / resync / link-regeneration / contribute cycle, preserving local facts.
- [x] Spaced-root session-context command with startup/resume/clear/compact fixture input.
- [x] Common workflow regressions, MANIFEST, skills and shellcheck.
- [x] Actual CLI instruction/skill discovery and saved Codex parent→worker→reviewer result receipt.
- [ ] Actual CLI hook trust/activation and event injection.
- [ ] Failure-injected model stop gates, all skills to completion and nested session resume.

The integration checkout passed all quality checks including its source tests. This template checkout passed 14 applicable checks; mypy/pytest are absent because no Python project is packaged here. Shared harness fixtures passed 15 tests.
CLI verification used Claude Code 2.1.291 and Codex 0.160.1. Ephemeral Codex worker startup failed with missing rollout context; a normal saved session succeeded. These observations do not guarantee all runtimes or releases.

## Resources and completion
Standard Python, bash and existing git/jq/gh; no new packages, GPU or research data required. Fixtures use temporary directories.
Draft PR only: unverified acceptance is explicit. Do not close the Issue, merge, or claim template-sync distribution before the upstream change is merged.
