"""Slack notifier implementation."""

from __future__ import annotations

import os
from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from qa.models import Answer, Question
from qa.notifiers.base import (
    NotifierPostError,
    QANotifier,
)

try:
    from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler
    from slack_bolt.async_app import AsyncApp

    SLACK_AVAILABLE = True
except ImportError:
    SLACK_AVAILABLE = False
    AsyncSocketModeHandler = None
    AsyncApp = None


if TYPE_CHECKING or SLACK_AVAILABLE:

    class SlackNotifier(QANotifier):
        """Slack integration for QA system using Socket Mode.

        Requires environment variables:
            SLACK_BOT_TOKEN: Bot token (xoxb-...)
            SLACK_APP_TOKEN: App token for Socket Mode (xapp-...)
            SLACK_CHANNEL: Channel ID or name to post questions

        Example:
            notifier = SlackNotifier()
            await notifier.start_listening(handle_answer)
            message_id = await notifier.post_question(question)
        """

        def __init__(
            self,
            bot_token: str | None = None,
            app_token: str | None = None,
            channel: str | None = None,
            github_repo: str | None = None,
        ) -> None:
            """Initialize Slack notifier.

            Args:
                bot_token: Slack bot token (or SLACK_BOT_TOKEN env var)
                app_token: Slack app token for Socket Mode (or SLACK_APP_TOKEN env var)
                channel: Channel to post to (or SLACK_CHANNEL env var)
                github_repo: GitHub repository URL for issue links

            Raises:
                ImportError: If slack_bolt is not installed
                ValueError: If required tokens are not provided
            """
            if not SLACK_AVAILABLE:
                raise ImportError(
                    "slack_bolt is required for Slack integration. "
                    "Install with: pip install slack_bolt"
                )

            self.bot_token = bot_token or os.environ.get("SLACK_BOT_TOKEN")
            self.app_token = app_token or os.environ.get("SLACK_APP_TOKEN")
            self.channel = channel or os.environ.get("SLACK_CHANNEL")
            self.github_repo = github_repo

            if not self.bot_token:
                raise ValueError("SLACK_BOT_TOKEN is required")
            if not self.app_token:
                raise ValueError("SLACK_APP_TOKEN is required")
            if not self.channel:
                raise ValueError("SLACK_CHANNEL is required")

            self._app: Any = AsyncApp(token=self.bot_token)
            self._handler: Any = None
            self._callback: Callable[[Answer], None] | None = None
            self._message_to_question: dict[str, str] = {}  # thread_ts -> question_id

            # Register message handler
            @self._app.event("message")
            async def handle_message(event: dict[str, Any], say: Callable[..., Any]) -> None:
                await self._handle_thread_reply(event, say)

        def _format_question(self, question: Question) -> str:
            """Format question for Slack message."""
            # Create issue link if github_repo is configured
            if self.github_repo:
                issue_link = f"<{self.github_repo}/issues/{question.issue}|#{question.issue}>"
                header = f"*{question.id}* - Issue {issue_link} への質問です"
            else:
                header = f"*{question.id}* (Issue #{question.issue})"

            lines = [
                header,
                "",
                question.question,
            ]

            if question.options:
                lines.append("")
                lines.append("*Options:*")
                for i, opt in enumerate(question.options, 1):
                    lines.append(f"  {i}. {opt}")

            if question.type.value == "provisional" and question.decision:
                lines.append("")
                lines.append(f"_Tentative decision: {question.decision}_")

            lines.append("")
            lines.append("Reply in thread to answer.")

            return "\n".join(lines)

        async def _handle_thread_reply(
            self, event: dict[str, Any], say: Callable[..., Any]
        ) -> None:
            """Handle a thread reply as an answer."""
            # Only process thread replies
            thread_ts = event.get("thread_ts")
            if not thread_ts:
                return

            # Check if this thread is for one of our questions
            question_id = self._message_to_question.get(thread_ts)
            if not question_id:
                return

            # Get answer details
            answer_text = event.get("text", "")
            user = event.get("user", "unknown")

            answer = Answer(
                id=question_id,
                answer=answer_text,
                by=user,
            )

            # Notify callback
            if self._callback:
                self._callback(answer)

            # Acknowledge with reaction (no notification) instead of message
            message_ts = event.get("ts")
            if message_ts:
                try:
                    await self._app.client.reactions_add(
                        channel=event.get("channel"),
                        timestamp=message_ts,
                        name="white_check_mark",  # ✅
                    )
                except Exception:
                    # Reaction may already exist, ignore
                    pass

        async def post_question(self, question: Question) -> str:
            """Post a question to the Slack channel.

            Args:
                question: The question to post

            Returns:
                Thread timestamp (message ID)

            Raises:
                NotifierPostError: If posting fails
            """
            try:
                result = await self._app.client.chat_postMessage(
                    channel=self.channel,
                    text=self._format_question(question),
                )
                thread_ts: str = result["ts"]

                # Track mapping for reply handling
                self._message_to_question[thread_ts] = question.id

                return thread_ts
            except Exception as e:
                raise NotifierPostError(f"Failed to post question: {e}") from e

        async def start_listening(
            self, callback: Callable[[Answer], None]
        ) -> None:
            """Start listening for answers in Socket Mode.

            Args:
                callback: Function to call when an answer is received
            """
            self._callback = callback
            self._handler = AsyncSocketModeHandler(self._app, self.app_token)
            await self._handler.start_async()

        async def stop_listening(self) -> None:
            """Stop listening for answers."""
            if self._handler:
                await self._handler.close_async()
                self._handler = None

        async def health_check(self) -> bool:
            """Check if connected to Slack.

            Returns:
                True if connected, False otherwise
            """
            try:
                result = await self._app.client.auth_test()
                return bool(result.get("ok", False))
            except Exception:
                return False

        def register_message_mapping(self, message_id: str, question_id: str) -> None:
            """Register a mapping from message ID to question ID.

            Used to restore mappings on bot restart for tracking thread replies.

            Args:
                message_id: Slack thread timestamp
                question_id: Question ID
            """
            self._message_to_question[message_id] = question_id
