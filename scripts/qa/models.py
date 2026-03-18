"""Data models for QA system."""

from datetime import UTC, datetime
from enum import StrEnum

from pydantic import BaseModel, Field


def _utcnow() -> datetime:
    """Get current UTC time as timezone-aware datetime."""
    return datetime.now(UTC)


class QuestionType(StrEnum):
    """Type of question determining how to proceed without an answer."""

    PROVISIONAL = "provisional"  # Make tentative decision, revise if answer differs
    DEFERRED = "deferred"  # Create stub, implement later when answer arrives


class Question(BaseModel):
    """A question requiring human input."""

    id: str = Field(..., description="Unique question identifier (e.g., Q001)")
    issue: int = Field(..., description="Related GitHub issue number")
    timestamp: datetime = Field(default_factory=_utcnow)
    question: str = Field(..., description="The question text")
    type: QuestionType = Field(..., description="How to proceed without answer")
    options: list[str] | None = Field(
        default=None, description="Available options for the answer"
    )
    decision: str | None = Field(
        default=None, description="Tentative decision (for provisional type)"
    )
    stub: str | None = Field(
        default=None, description="Stub code/placeholder (for deferred type)"
    )
    message_id: str | None = Field(
        default=None, description="Platform-specific message ID for tracking"
    )

    def to_jsonl(self) -> str:
        """Serialize to JSONL format."""
        return self.model_dump_json()

    @classmethod
    def from_jsonl(cls, line: str) -> "Question":
        """Deserialize from JSONL format."""
        return cls.model_validate_json(line)


class Answer(BaseModel):
    """An answer to a question."""

    id: str = Field(..., description="Question ID this answers")
    timestamp: datetime = Field(default_factory=_utcnow)
    answer: str = Field(..., description="The answer text")
    by: str = Field(..., description="Who provided the answer")

    def to_jsonl(self) -> str:
        """Serialize to JSONL format."""
        return self.model_dump_json()

    @classmethod
    def from_jsonl(cls, line: str) -> "Answer":
        """Deserialize from JSONL format."""
        return cls.model_validate_json(line)
