"""Configuration for QA system."""

import sys
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field

# QA データの既定の置き場所。内部開発メモは `.dev/` に置く規約に従う
# (.claude/rules/template/doc-principles.md)。`docs/` は公開ドキュメント用であり、
# QA ログを置くとリリース成果物に混入する。
DEFAULT_QA_DIR = ".dev/qa"

# 移設前の置き場所。**自動でフォールバックしない**（#122 D2）。
# 黙って旧パスを読むと「新パスに移したつもりで旧データを見続ける」silent-wrong になり、
# 黙って新パスだけ見ると「既存の QA ログが無言で無視される」silent-wrong になる。
# どちらも避けるため、検出したら loud に案内して利用者に移行を選ばせる。
LEGACY_QA_DIR = "docs/qa"


class SlackConfig(BaseModel):
    """Slack-specific configuration."""

    channel: str = Field(..., description="Channel ID or name")


class DiscordConfig(BaseModel):
    """Discord-specific configuration."""

    channel_id: int = Field(..., description="Channel ID")


class QAConfig(BaseModel):
    """QA system configuration."""

    notifier: Literal["slack", "discord"] = Field(
        default="slack", description="Notification platform to use"
    )
    qa_dir: str = Field(
        default=DEFAULT_QA_DIR, description="Directory for questions/answers files"
    )
    github_repo: str | None = Field(
        default=None, description="GitHub repository URL (e.g., https://github.com/owner/repo)"
    )
    slack: SlackConfig | None = Field(default=None)
    discord: DiscordConfig | None = Field(default=None)

    @classmethod
    def load(cls, path: Path | None = None) -> "QAConfig":
        """Load configuration from YAML file.

        Args:
            path: Path to config file. Defaults to .claude/qa-config.yaml

        Returns:
            Loaded configuration
        """
        if path is None:
            path = Path(".claude/qa-config.yaml")

        if not path.exists():
            return cls()

        with open(path) as f:
            data = yaml.safe_load(f) or {}

        return cls.model_validate(data)

    def get_qa_dir(self) -> Path:
        """Get QA directory as Path.

        Emits a loud warning (never a silent fallback) when QA data is still
        sitting in the legacy ``docs/qa`` directory.
        """
        qa_dir = Path(self.qa_dir)
        warn_if_legacy_qa_data(qa_dir)
        return qa_dir


def legacy_qa_warning(qa_dir: Path) -> str | None:
    """Return a migration notice if legacy QA data would be ignored.

    Returns ``None`` when there is nothing to warn about, i.e. when the legacy
    directory holds no data, or when the configured directory *is* the legacy
    directory (an explicit choice made in ``.claude/qa-config.yaml``).

    The data is never moved automatically: ``questions.jsonl`` / ``answers.jsonl``
    are user data, and a silent relocation would be indistinguishable from data
    loss if the paths were configured on purpose.
    """
    legacy = Path(LEGACY_QA_DIR)
    if qa_dir.resolve() == legacy.resolve():
        return None

    legacy_files = [
        legacy / name
        for name in ("questions.jsonl", "answers.jsonl")
        if (legacy / name).exists() and (legacy / name).stat().st_size > 0
    ]
    if not legacy_files:
        return None

    listed = ", ".join(str(p) for p in legacy_files)
    return (
        f"[QA] 旧パスにデータが残っています: {listed}\n"
        f"[QA] 現在の参照先は '{qa_dir}' です。旧データは読み込まれません。\n"
        f"[QA] 移行するには次を実行してください（自動では移動しません）:\n"
        f"[QA]   mkdir -p {qa_dir} && git mv {legacy}/*.jsonl {qa_dir}/\n"
        f"[QA] 旧パスを使い続ける場合は .claude/qa-config.yaml に "
        f"'qa_dir: {LEGACY_QA_DIR}' を明示してください。"
    )


def warn_if_legacy_qa_data(qa_dir: Path) -> bool:
    """Print the legacy-data notice to stderr. Returns True if one was printed."""
    message = legacy_qa_warning(qa_dir)
    if message is None:
        return False
    print(message, file=sys.stderr)
    return True
