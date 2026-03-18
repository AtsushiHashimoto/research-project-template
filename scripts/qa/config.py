"""Configuration for QA system."""

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field


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
        default="docs/qa", description="Directory for questions/answers files"
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
        """Get QA directory as Path."""
        return Path(self.qa_dir)
