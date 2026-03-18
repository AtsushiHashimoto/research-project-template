"""Discord notifier implementation."""

from __future__ import annotations

import asyncio
import contextlib
import os
from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from qa.models import Answer, Question
from qa.notifiers.base import (
    NotifierPostError,
    QANotifier,
)

try:
    import discord
    from discord.ext import commands

    DISCORD_AVAILABLE = True
except ImportError:
    DISCORD_AVAILABLE = False
    discord = None
    commands = None


if TYPE_CHECKING or DISCORD_AVAILABLE:

    class DiscordNotifier(QANotifier):
        """Discord integration for QA system.

        Requires environment variables:
            DISCORD_BOT_TOKEN: Bot token
            DISCORD_CHANNEL_ID: Channel ID to post questions

        Example:
            notifier = DiscordNotifier()
            await notifier.start_listening(handle_answer)
            message_id = await notifier.post_question(question)
        """

        def __init__(
            self,
            bot_token: str | None = None,
            channel_id: int | str | None = None,
        ) -> None:
            """Initialize Discord notifier.

            Args:
                bot_token: Discord bot token (or DISCORD_BOT_TOKEN env var)
                channel_id: Channel ID to post to (or DISCORD_CHANNEL_ID env var)

            Raises:
                ImportError: If discord.py is not installed
                ValueError: If required tokens are not provided
            """
            if not DISCORD_AVAILABLE:
                raise ImportError(
                    "discord.py is required for Discord integration. "
                    "Install with: pip install discord.py"
                )

            self.bot_token = bot_token or os.environ.get("DISCORD_BOT_TOKEN")
            channel_id_str = channel_id or os.environ.get("DISCORD_CHANNEL_ID")

            if not self.bot_token:
                raise ValueError("DISCORD_BOT_TOKEN is required")
            if not channel_id_str:
                raise ValueError("DISCORD_CHANNEL_ID is required")

            self.channel_id = int(channel_id_str)

            intents = discord.Intents.default()
            intents.message_content = True
            self._bot: Any = commands.Bot(command_prefix="!", intents=intents)
            self._callback: Callable[[Answer], None] | None = None
            self._message_to_question: dict[int, str] = {}  # message_id -> question_id
            self._channel: Any = None
            self._ready_event = asyncio.Event()
            self._task: asyncio.Task[None] | None = None

            # Register event handlers
            @self._bot.event
            async def on_ready() -> None:
                channel = self._bot.get_channel(self.channel_id)
                if channel is not None:
                    self._channel = channel
                self._ready_event.set()

            @self._bot.event
            async def on_message(message: Any) -> None:
                await self._handle_reply(message)

        def _format_question(self, question: Question) -> str:
            """Format question for Discord message."""
            lines = [
                f"**{question.id}** (Issue #{question.issue})",
                "",
                question.question,
            ]

            if question.options:
                lines.append("")
                lines.append("**Options:**")
                for i, opt in enumerate(question.options, 1):
                    lines.append(f"  {i}. {opt}")

            if question.type.value == "provisional" and question.decision:
                lines.append("")
                lines.append(f"*Tentative decision: {question.decision}*")

            lines.append("")
            lines.append("Reply to this message to answer.")

            return "\n".join(lines)

        async def _handle_reply(self, message: Any) -> None:
            """Handle a reply as an answer."""
            # Ignore bot messages
            if message.author.bot:
                return

            # Only process replies
            if not message.reference or not message.reference.message_id:
                return

            # Check if this is a reply to one of our questions
            question_id = self._message_to_question.get(message.reference.message_id)
            if not question_id:
                return

            answer = Answer(
                id=question_id,
                answer=message.content,
                by=str(message.author),
            )

            # Notify callback
            if self._callback:
                self._callback(answer)

            # Acknowledge
            await message.reply("Answer recorded.")

        async def post_question(self, question: Question) -> str:
            """Post a question to the Discord channel.

            Args:
                question: The question to post

            Returns:
                Message ID as string

            Raises:
                NotifierPostError: If posting fails
            """
            if not self._channel:
                raise NotifierPostError("Not connected to Discord channel")

            try:
                message = await self._channel.send(self._format_question(question))
                message_id: int = message.id

                # Track mapping for reply handling
                self._message_to_question[message_id] = question.id

                return str(message_id)
            except Exception as e:
                raise NotifierPostError(f"Failed to post question: {e}") from e

        async def start_listening(
            self, callback: Callable[[Answer], None]
        ) -> None:
            """Start listening for answers.

            Args:
                callback: Function to call when an answer is received
            """
            self._callback = callback

            async def run_bot() -> None:
                await self._bot.start(self.bot_token)

            self._task = asyncio.create_task(run_bot())
            await self._ready_event.wait()

        async def stop_listening(self) -> None:
            """Stop listening for answers."""
            await self._bot.close()
            if self._task:
                self._task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self._task
                self._task = None

        async def health_check(self) -> bool:
            """Check if connected to Discord.

            Returns:
                True if connected, False otherwise
            """
            return bool(self._bot.is_ready() and self._channel is not None)
