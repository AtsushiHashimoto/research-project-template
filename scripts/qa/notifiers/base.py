"""Abstract base class for QA notifiers."""

from abc import ABC, abstractmethod
from collections.abc import Callable

from qa.models import Answer, Question


class QANotifier(ABC):
    """Abstract base class for notification platform integrations.

    Implementations handle posting questions to and receiving answers from
    messaging platforms like Slack, Discord, etc.

    Example:
        class MyNotifier(QANotifier):
            async def post_question(self, question):
                # Post to platform
                return "message_id_123"

            async def start_listening(self, callback):
                # Start listening for answers
                pass

            async def stop_listening(self):
                # Stop listening
                pass
    """

    @abstractmethod
    async def post_question(self, question: Question) -> str:
        """Post a question to the messaging platform.

        Args:
            question: The question to post

        Returns:
            Platform-specific message ID for tracking

        Raises:
            NotifierError: If posting fails
        """
        ...

    @abstractmethod
    async def start_listening(
        self, callback: Callable[[Answer], None]
    ) -> None:
        """Start listening for answers.

        When an answer is received, the callback is invoked with the Answer.

        Args:
            callback: Function to call when an answer is received
        """
        ...

    @abstractmethod
    async def stop_listening(self) -> None:
        """Stop listening for answers."""
        ...

    @abstractmethod
    async def health_check(self) -> bool:
        """Check if the notifier is connected and ready.

        Returns:
            True if ready, False otherwise
        """
        ...

    def register_message_mapping(self, message_id: str, question_id: str) -> None:
        """Register a mapping from message ID to question ID.

        Used to restore mappings on bot restart for tracking thread replies.

        Args:
            message_id: Platform-specific message ID
            question_id: Question ID
        """
        pass  # Default no-op, override in subclasses that need it


class NotifierError(Exception):
    """Base exception for notifier errors."""

    pass


class NotifierConnectionError(NotifierError):
    """Raised when notifier cannot connect to the platform."""

    pass


class NotifierPostError(NotifierError):
    """Raised when posting a message fails."""

    pass
