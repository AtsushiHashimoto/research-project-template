"""File watcher for questions.jsonl using inotify."""

import asyncio
import contextlib
from collections.abc import Callable
from pathlib import Path

try:
    import inotify.adapters

    INOTIFY_AVAILABLE = True
except ImportError:
    INOTIFY_AVAILABLE = False


class QAWatcher:
    """Watch questions.jsonl for new questions using inotify.

    Falls back to polling if inotify is not available.

    Example:
        watcher = QAWatcher(Path("docs/qa"))
        await watcher.start(on_new_question)
    """

    def __init__(self, qa_dir: Path, poll_interval: float = 5.0) -> None:
        """Initialize watcher.

        Args:
            qa_dir: Directory containing questions.jsonl
            poll_interval: Polling interval in seconds (fallback mode)
        """
        self.qa_dir = qa_dir
        self.questions_file = qa_dir / "questions.jsonl"
        self.poll_interval = poll_interval
        self._running = False
        self._task: asyncio.Task | None = None  # type: ignore[type-arg]
        self._last_line_count = 0

    def _count_lines(self) -> int:
        """Count non-empty lines in questions file."""
        if not self.questions_file.exists():
            return 0
        with open(self.questions_file) as f:
            return sum(1 for line in f if line.strip())

    async def _watch_inotify(
        self, callback: Callable[[Path], None]
    ) -> None:
        """Watch using inotify (Linux only)."""
        if not INOTIFY_AVAILABLE:
            raise RuntimeError("inotify not available")

        i = inotify.adapters.Inotify()
        i.add_watch(str(self.qa_dir))

        self._last_line_count = self._count_lines()

        loop = asyncio.get_event_loop()
        while self._running:
            # Run blocking inotify in executor
            events = await loop.run_in_executor(
                None, lambda: list(i.event_gen(yield_nones=False, timeout_s=1))
            )

            for event in events:
                (_, type_names, path, filename) = event
                if filename == "questions.jsonl" and "IN_MODIFY" in type_names:
                    new_count = self._count_lines()
                    if new_count > self._last_line_count:
                        self._last_line_count = new_count
                        callback(self.questions_file)

    async def _watch_poll(
        self, callback: Callable[[Path], None]
    ) -> None:
        """Watch using polling (fallback)."""
        self._last_line_count = self._count_lines()

        while self._running:
            await asyncio.sleep(self.poll_interval)

            new_count = self._count_lines()
            if new_count > self._last_line_count:
                self._last_line_count = new_count
                callback(self.questions_file)

    async def start(self, callback: Callable[[Path], None]) -> None:
        """Start watching for new questions.

        Args:
            callback: Function to call when new questions are added
        """
        self._running = True

        if INOTIFY_AVAILABLE:
            self._task = asyncio.create_task(self._watch_inotify(callback))
        else:
            self._task = asyncio.create_task(self._watch_poll(callback))

    async def stop(self) -> None:
        """Stop watching."""
        self._running = False
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
            self._task = None
