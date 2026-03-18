"""QA Bot - Watches for questions and posts to messaging platform."""

import asyncio
import logging
from pathlib import Path

from qa.models import Answer, Question
from qa.notifiers.base import QANotifier
from qa.store import QAStore
from qa.watcher import QAWatcher

logger = logging.getLogger(__name__)


class QABot:
    """Bot that watches questions.jsonl and posts to messaging platform.

    Flow:
    1. Watch questions.jsonl for new questions (inotify)
    2. Post new questions to platform (Slack/Discord)
    3. Listen for answers from platform
    4. Write answers to answers.jsonl

    Example:
        from qa.notifiers.slack import SlackNotifier

        bot = QABot(
            qa_dir=Path("docs/qa"),
            notifier=SlackNotifier(),
        )
        await bot.run()
    """

    def __init__(
        self,
        qa_dir: Path,
        notifier: QANotifier,
    ) -> None:
        """Initialize QA bot.

        Args:
            qa_dir: Directory containing questions.jsonl and answers.jsonl
            notifier: Messaging platform notifier
        """
        self.store = QAStore(qa_dir)
        self.notifier = notifier
        self.watcher = QAWatcher(qa_dir)
        self._posted_questions: set[str] = set()
        self._running = False

    def _on_new_questions(self, path: Path) -> None:
        """Handle new questions file update."""
        questions = self.store.get_unanswered_questions()
        for question in questions:
            if question.id not in self._posted_questions:
                # Schedule posting (we're in a sync callback)
                asyncio.create_task(self._post_question(question))

    async def _post_question(self, question: Question) -> None:
        """Post a question to the messaging platform."""
        try:
            message_id = await self.notifier.post_question(question)
            self._posted_questions.add(question.id)

            # Save message_id to questions.jsonl for later thread replies
            if message_id:
                self.store.update_question_message_id(question.id, message_id)
                logger.info(f"Posted question {question.id} (message_id={message_id})")
            else:
                logger.warning(f"Posted question {question.id} but no message_id returned")
        except Exception as e:
            logger.error(f"Failed to post question {question.id}: {e}")

    def _on_answer(self, answer: Answer) -> None:
        """Handle answer received from messaging platform."""
        try:
            self.store.add_answer(answer)
            logger.info(f"Recorded answer for {answer.id} from {answer.by}")
        except Exception as e:
            logger.error(f"Failed to record answer for {answer.id}: {e}")

    async def run(self) -> None:
        """Run the bot (blocking).

        Posts any existing unanswered questions, then watches for new ones.
        """
        self._running = True

        # Check connection
        if not await self.notifier.health_check():
            raise RuntimeError("Notifier health check failed")

        # Restore message mappings for existing questions (for thread reply tracking)
        all_questions = self.store.get_all_questions()
        for question in all_questions:
            if question.message_id:
                self.notifier.register_message_mapping(question.message_id, question.id)
                self._posted_questions.add(question.id)
                logger.info(f"Restored mapping for {question.id} (message_id={question.message_id})")

        # Post any existing unanswered questions (without message_id)
        unanswered = self.store.get_unanswered_questions()
        for question in unanswered:
            if not question.message_id:
                await self._post_question(question)

        # Start listening for answers
        await self.notifier.start_listening(self._on_answer)

        # Start watching for new questions
        await self.watcher.start(self._on_new_questions)

        logger.info("QA Bot running. Press Ctrl+C to stop.")

        try:
            while self._running:
                await asyncio.sleep(1)
        except asyncio.CancelledError:
            pass
        finally:
            await self.stop()

    async def stop(self) -> None:
        """Stop the bot."""
        self._running = False
        await self.watcher.stop()
        await self.notifier.stop_listening()
        logger.info("QA Bot stopped.")
