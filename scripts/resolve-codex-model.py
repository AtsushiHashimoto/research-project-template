#!/usr/bin/env python3
"""Resolve Codex roles from the shared policy without using Claude model aliases."""

import json
import os
import subprocess
import sys
from pathlib import Path


def main(args):
    root = Path(
        subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True
        ).strip()
    )
    policy = root / ".claude/model-policy.json"
    local_path = root / ".claude/model-policy.local.json"
    data = json.loads(policy.read_text())
    config = data["agents"]["codex"]
    local = json.loads(local_path.read_text()) if local_path.exists() else {}
    local_config = local.get("agents", {}).get("codex", {})
    if not isinstance(config, dict) or not isinstance(local_config, dict):
        raise TypeError("Codex shared/local policy must be an object")
    overrides = config.get("overrides", {})
    if not isinstance(overrides, dict):
        raise TypeError("Codex overrides must be an object")

    def models(value, field):
        if not isinstance(value, list) or any(
            not isinstance(m, str) or not m for m in value
        ):
            raise ValueError(f"{field} must be an array of nonempty model strings")
        return value

    disabled = set(models(config.get("disabled", []), "disabled")) | set(
        models(local_config.get("disabled", []), "local disabled")
    )
    disabled.update(
        filter(None, os.environ.get("CODEX_MODEL_POLICY_DISABLE", "").split(","))
    )

    def resolve(role):
        spec = config["roles"][role]
        if role in overrides and (
            not isinstance(overrides[role], str) or not overrides[role]
        ):
            raise ValueError(f"override for {role} must be a nonempty model string")
        candidates = (
            ([overrides[role]] if role in overrides else [])
            + [spec["primary"]]
            + models(spec["fallback"], "fallback")
        )
        for model in candidates:
            if not isinstance(model, str) or not model:
                raise ValueError(f"invalid model for {role}")
            if model in {"opus", "sonnet", "haiku"}:
                raise ValueError(f"Claude model alias in Codex policy: {model}")
        for model in candidates:
            if model not in disabled:
                return model
        raise ValueError(
            f"all models disabled for Codex role {role}; explicitly update policy"
        )

    if len(args) == 1 and args[0] == "--list":
        for role in config["roles"]:
            print(f"{role}\t{resolve(role)}")
    elif len(args) == 2 and args[0] in {"--disable", "--enable"}:
        model = args[1]
        values = set(local_config.get("disabled", []))
        if args[0] == "--disable":
            values.add(model)
        else:
            values.discard(model)
        local.setdefault("agents", {}).setdefault("codex", {})["disabled"] = sorted(
            values
        )
        local_path.write_text(json.dumps(local, ensure_ascii=False, indent=2) + "\n")
        if args[0] == "--enable" and model in (
            set(config.get("disabled", []))
            | set(
                filter(
                    None, os.environ.get("CODEX_MODEL_POLICY_DISABLE", "").split(",")
                )
            )
        ):
            raise ValueError(
                f"{model} still disabled by shared policy or CODEX_MODEL_POLICY_DISABLE"
            )
        print(f"{args[0]} {model}: Codex local policy")
    elif len(args) == 1 and not args[0].startswith("--"):
        print(resolve(args[0]))
    else:
        raise ValueError(
            "usage: --agent codex <role> | --list | --disable <model> | --enable <model>"
        )


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.CalledProcessError,
    ) as exc:
        print(f"[resolve-model] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
